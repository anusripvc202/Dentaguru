import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/referral_model.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/widgets/dental_ads_banner.dart';

const Color _kSurfaceBg = Color(0xFFF7F9FC);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kSoftNavy = Color(0xFFEBF2FE);
const Color _kSoftBorder = Color(0xFFD4E3FC);
const Color _kSoftRedBg = Color(0xFFFEF2F2);
const Color _kSoftRedBorder = Color(0xFFFECACA);

// =============================================================================
// TOP HEADER (SHARED BY OVERVIEW & BOOKINGS? -> HEADER DESIGN MATCHES SCREENSHOTS)
// =============================================================================

class GsHealthClinicHeader extends StatelessWidget {
  final String clinicName;
  final int unreadNotifications;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;

  const GsHealthClinicHeader({
    super.key,
    required this.clinicName,
    required this.unreadNotifications,
    required this.onNotifications,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final displayClinic =
        clinicName.trim().isNotEmpty ? clinicName.trim() : 'Clinic Workspace';
    final canPop = Navigator.of(context).canPop();

    return Container(
      color: _kSurfaceBg,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (canPop) ...[
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: _kBorder),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      size: 18,
                      color: AppTheme.gsNavy,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              const GsHealthLogo(
                height: 28,
                alignment: Alignment.centerLeft,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Clinic dashboard',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMedium,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayClinic,
                      key: const Key('clinic_header_name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.gsNavy,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _ClinicCircleIconButton(
                key: const Key('clinic_notifications_button'),
                icon: Icons.notifications_none_rounded,
                badgeCount: unreadNotifications,
                onTap: onNotifications,
              ),
              const SizedBox(width: 10),
              _ClinicCircleIconButton(
                key: const Key('clinic_profile_button'),
                icon: Icons.person_outline_rounded,
                onTap: onProfile,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClinicCircleIconButton extends StatelessWidget {
  final IconData icon;
  final int badgeCount;
  final VoidCallback onTap;

  const _ClinicCircleIconButton({
    super.key,
    required this.icon,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _kBorder, width: 1.2),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, color: AppTheme.gsNavy, size: 22),
              if (badgeCount > 0)
                Positioned(
                  top: 2,
                  right: 0,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.gsRed,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CLINIC OVERVIEW (ONE CONTINUOUS SCROLLABLE PAGE)
// =============================================================================

class GsHealthClinicOverview extends StatefulWidget {
  final String clinicName;
  final String clinicLocation;
  final String coverImageUrl;
  final Uint8List? coverImageBytes;
  final bool isFeatured;
  final String featuredPlan;
  final int unreadNotifications;
  final int referralsCount;
  final int visitsTodayCount;
  final int awaitingConfirmationCount;
  final int completedVisitsCount;
  final List<DoctorModel> attachedDoctors;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final VoidCallback onEditDetails;
  final VoidCallback onOpenFeaturedPlan;
  final VoidCallback onOpenReferrals;
  final VoidCallback onOpenAdvertise;
  final void Function(String bookingFilter) onTapBookingsStat;
  final VoidCallback onAddDoctor;
  final Future<void> Function() onRefresh;
  final void Function(DoctorModel doc) onToggleDoctorStatus;
  final void Function(DoctorModel doc) onViewDoctorProfile;
  final void Function(DoctorModel doc) onEditDoctor;
  final void Function(DoctorModel doc) onManageDoctorSlots;
  final void Function(DoctorModel doc) onRemoveDoctor;

  const GsHealthClinicOverview({
    super.key,
    required this.clinicName,
    required this.clinicLocation,
    required this.coverImageUrl,
    this.coverImageBytes,
    required this.isFeatured,
    required this.featuredPlan,
    required this.unreadNotifications,
    required this.referralsCount,
    required this.visitsTodayCount,
    required this.awaitingConfirmationCount,
    required this.completedVisitsCount,
    required this.attachedDoctors,
    required this.onNotifications,
    required this.onProfile,
    required this.onEditDetails,
    required this.onOpenFeaturedPlan,
    required this.onOpenReferrals,
    required this.onOpenAdvertise,
    required this.onTapBookingsStat,
    required this.onAddDoctor,
    required this.onRefresh,
    required this.onToggleDoctorStatus,
    required this.onViewDoctorProfile,
    required this.onEditDoctor,
    required this.onManageDoctorSlots,
    required this.onRemoveDoctor,
  });

  @override
  State<GsHealthClinicOverview> createState() => _GsHealthClinicOverviewState();
}

class _GsHealthClinicOverviewState extends State<GsHealthClinicOverview> {
  final PageController _adController = PageController();
  int _adIndex = 0;

  @override
  void dispose() {
    _adController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinicAds = sponsoredAdsForClinic();
    final cleanLocation = widget.clinicLocation.trim();
    final doctors = widget.attachedDoctors;

    return Container(
      color: _kSurfaceBg,
      child: Column(
        children: [
          GsHealthClinicHeader(
            clinicName: widget.clinicName,
            unreadNotifications: widget.unreadNotifications,
            onNotifications: widget.onNotifications,
            onProfile: widget.onProfile,
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.gsNavy,
              onRefresh: widget.onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Clinic Cover Card + Edit details pill
                    _ClinicCoverCard(
                      clinicName: widget.clinicName,
                      coverImageUrl: widget.coverImageUrl,
                      coverImageBytes: widget.coverImageBytes,
                      onEditDetails: widget.onEditDetails,
                    ),
                    const SizedBox(height: 10),

                    // 2. Clinic Address Row
                    InkWell(
                      onTap: widget.onEditDetails,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.location_on_outlined,
                                size: 17,
                                color: AppTheme.gsRed,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                cleanLocation.isNotEmpty
                                    ? cleanLocation
                                    : 'Location not set — tap Edit details to add address',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: cleanLocation.isNotEmpty
                                      ? AppTheme.textMedium
                                      : AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. Sponsored Carousel
                    if (clinicAds.isNotEmpty) ...[
                      SizedBox(
                        height: 148,
                        child: PageView.builder(
                          controller: _adController,
                          itemCount: clinicAds.length,
                          onPageChanged: (idx) => setState(() => _adIndex = idx),
                          itemBuilder: (_, idx) => _ClinicAdCard(
                            ad: clinicAds[idx],
                            onTap: () => _launchSponsor(clinicAds[idx].website),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(clinicAds.length, (i) {
                          final active = i == _adIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            height: 6,
                            width: active ? 20 : 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? AppTheme.gsNavy
                                  : const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // 4. Featured Clinic Card
                    _ClinicFeaturedCard(
                      isFeatured: widget.isFeatured,
                      featuredPlan: widget.featuredPlan,
                      onTap: widget.onOpenFeaturedPlan,
                    ),
                    const SizedBox(height: 12),

                    // 5. Patient Referrals Card
                    _ClinicActionListCard(
                      key: const Key('clinic_patient_referrals_card'),
                      icon: Icons.medical_information_outlined,
                      iconColor: AppTheme.gsNavy,
                      backgroundColor: Colors.white,
                      borderColor: _kBorder,
                      title: 'Patient referrals',
                      subtitle:
                          'Patients referred to you by dentists, with their files',
                      badgeCount: widget.referralsCount,
                      onTap: widget.onOpenReferrals,
                    ),
                    const SizedBox(height: 12),

                    // 6. Advertise on GS HEALTH Card
                    _ClinicActionListCard(
                      key: const Key('clinic_advertise_card'),
                      icon: Icons.campaign_outlined,
                      iconColor: AppTheme.gsRed,
                      backgroundColor: _kSoftNavy,
                      borderColor: _kSoftBorder,
                      title: 'Advertise on GS HEALTH',
                      subtitle:
                          'Request a sponsored banner for patients and dentists',
                      onTap: widget.onOpenAdvertise,
                    ),
                    const SizedBox(height: 18),

                    // 7. 2x2 Stats Grid
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 12.0;
                        final cardWidth = (constraints.maxWidth - spacing) / 2;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            _ClinicStatCard(
                              key: const Key('clinic_stat_visits_today'),
                              width: cardWidth,
                              value: widget.visitsTodayCount,
                              label: 'Visits today',
                              valueColor: AppTheme.gsNavy,
                              onTap: () => widget.onTapBookingsStat('All'),
                            ),
                            _ClinicStatCard(
                              key: const Key('clinic_stat_awaiting'),
                              width: cardWidth,
                              value: widget.awaitingConfirmationCount,
                              label: 'Awaiting confirmation',
                              valueColor: widget.awaitingConfirmationCount > 0
                                  ? AppTheme.gsRed
                                  : AppTheme.gsNavy,
                              accentBorder: widget.awaitingConfirmationCount > 0,
                              onTap: () => widget.onTapBookingsStat('Pending'),
                            ),
                            _ClinicStatCard(
                              key: const Key('clinic_stat_completed'),
                              width: cardWidth,
                              value: widget.completedVisitsCount,
                              label: 'Completed visits',
                              valueColor: AppTheme.gsNavy,
                              onTap: () => widget.onTapBookingsStat('Completed'),
                            ),
                            _ClinicStatCard(
                              key: const Key('clinic_stat_doctors'),
                              width: cardWidth,
                              value: doctors.length,
                              label: 'Attached doctors',
                              valueColor: AppTheme.gsRed,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // 8. Attached Doctors Section
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Attached doctors (${doctors.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.gsNavy,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          key: const Key('clinic_add_doctor_button'),
                          onPressed: widget.onAddDoctor,
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                          label: const Text(
                            'Add Doctor',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.gsRed,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (doctors.isEmpty)
                      const _ClinicEmptyCard(
                        icon: Icons.medical_services_outlined,
                        title: 'No doctors attached yet',
                        subtitle:
                            'Add verified specialists to your clinic team using Add Doctor.',
                      )
                    else
                      ...doctors.map(
                        (doc) => _ClinicDoctorCard(
                          doc: doc,
                          onToggleStatus: () => widget.onToggleDoctorStatus(doc),
                          onViewProfile: () => widget.onViewDoctorProfile(doc),
                          onEdit: () => widget.onEditDoctor(doc),
                          onManageSlots: () => widget.onManageDoctorSlots(doc),
                          onRemove: () => widget.onRemoveDoctor(doc),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchSponsor(String website) async {
    final uri = Uri.tryParse(website);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _ClinicCoverCard extends StatelessWidget {
  final String clinicName;
  final String coverImageUrl;
  final Uint8List? coverImageBytes;
  final VoidCallback onEditDetails;

  const _ClinicCoverCard({
    required this.clinicName,
    required this.coverImageUrl,
    this.coverImageBytes,
    required this.onEditDetails,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 190,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: _kBorder),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coverImageBytes != null)
              Image.memory(coverImageBytes!, fit: BoxFit.cover)
            else if (coverImageUrl.trim().isNotEmpty)
              Image.network(
                coverImageUrl.trim(),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _ClinicCoverPlaceholder(clinicName: clinicName),
              )
            else
              _ClinicCoverPlaceholder(clinicName: clinicName),
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                color: AppTheme.gsNavy.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  key: const Key('clinic_edit_details_button'),
                  onTap: onEditDetails,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Edit details',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClinicCoverPlaceholder extends StatelessWidget {
  final String clinicName;

  const _ClinicCoverPlaceholder({required this.clinicName});

  @override
  Widget build(BuildContext context) {
    final clean = clinicName.trim();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.gsNavy, Color(0xFF0A4380), Color(0xFF143E75)],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -12,
            child: Icon(
              Icons.local_hospital_rounded,
              size: 130,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.gsRed,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'GS HEALTH CLINIC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                clean.isNotEmpty ? clean : 'Add clinic cover photo',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap Edit details to update clinic photo and location',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClinicAdCard extends StatelessWidget {
  final DentalAd ad;
  final VoidCallback onTap;

  const _ClinicAdCard({required this.ad, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0A3D7A), AppTheme.gsNavy, Color(0xFF001B3B)],
                  ),
                ),
              ),
              Positioned(
                right: -12,
                top: 12,
                child: Icon(
                  ad.icon,
                  size: 130,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.gsRed,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'SPONSORED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.open_in_new_rounded,
                          color: Colors.white.withValues(alpha: 0.85),
                          size: 18,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      ad.brand,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ad.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
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

class _ClinicFeaturedCard extends StatelessWidget {
  final bool isFeatured;
  final String featuredPlan;
  final VoidCallback onTap;

  const _ClinicFeaturedCard({
    required this.isFeatured,
    required this.featuredPlan,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isFeatured ? const Color(0xFFFFF5F5) : Colors.white;
    final borderColor = isFeatured ? _kSoftRedBorder : _kBorder;
    final title =
        isFeatured ? "You're a Featured clinic" : 'Promote as a Featured clinic';
    final subtitle = isFeatured
        ? (featuredPlan.trim().isNotEmpty
            ? 'Active plan: ${featuredPlan.trim()} · Tap to manage'
            : 'Manage or renew your Featured plan')
        : 'Stand out in GS HEALTH patient & dentist searches';

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: const Key('clinic_featured_card'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isFeatured
                      ? AppTheme.gsRed.withValues(alpha: 0.12)
                      : _kSoftNavy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isFeatured ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: AppTheme.gsRed,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.gsNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.gsNavy,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClinicActionListCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final String title;
  final String subtitle;
  final int badgeCount;
  final VoidCallback onTap;

  const _ClinicActionListCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.title,
    required this.subtitle,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: Icon(icon, color: iconColor, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.gsNavy,
                            ),
                          ),
                        ),
                        if (badgeCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.gsRed,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.gsNavy,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClinicStatCard extends StatelessWidget {
  final double width;
  final int value;
  final String label;
  final Color valueColor;
  final bool accentBorder;
  final VoidCallback? onTap;

  const _ClinicStatCard({
    super.key,
    required this.width,
    required this.value,
    required this.label,
    required this.valueColor,
    this.accentBorder = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            constraints: const BoxConstraints(minHeight: 100),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: accentBorder ? _kSoftRedBorder : _kBorder,
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$value',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClinicDoctorCard extends StatelessWidget {
  final DoctorModel doc;
  final VoidCallback onToggleStatus;
  final VoidCallback onViewProfile;
  final VoidCallback onEdit;
  final VoidCallback onManageSlots;
  final VoidCallback onRemove;

  const _ClinicDoctorCard({
    required this.doc,
    required this.onToggleStatus,
    required this.onViewProfile,
    required this.onEdit,
    required this.onManageSlots,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = doc.status.toLowerCase() != 'offline' &&
        doc.status.toLowerCase() != 'inactive';
    final statusLabel = isActive ? 'Active' : 'Inactive';
    final verStatus = doc.verificationStatus.trim().toUpperCase();
    final isVerified = verStatus.isEmpty || verStatus == 'VERIFIED';

    return Container(
      key: Key('clinic_doctor_card_${doc.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                key: Key('clinic_doctor_image_${doc.id}'),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 60,
                  height: 60,
                  color: _kSoftNavy,
                  child: doc.photoBytes != null
                      ? Image.memory(doc.photoBytes!, fit: BoxFit.cover)
                      : _ClinicDoctorInitialsAvatar(name: doc.name),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  doc.name,
                                  key: Key('clinic_doctor_name_${doc.id}'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.gsNavy,
                                  ),
                                ),
                              ),
                              if (isVerified) ...[
                                const SizedBox(width: 5),
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: AppTheme.gsNavy,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isVerified ? _kSoftNavy : _kSoftRedBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color:
                                  isVerified ? _kSoftBorder : _kSoftRedBorder,
                            ),
                          ),
                          child: Text(
                            isVerified ? 'VERIFIED' : verStatus,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color:
                                  isVerified ? AppTheme.gsNavy : AppTheme.gsRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            doc.specialty,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                        Text(
                          ' · ${doc.experienceYears} yrs',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            doc.clinicName.trim().isNotEmpty
                                ? doc.clinicName
                                : 'Clinic Staff',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          key: Key('clinic_status_toggle_${doc.id}'),
                          onTap: onToggleStatus,
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: isActive ? _kSoftNavy : _kSoftRedBg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color:
                                    isActive ? _kSoftBorder : _kSoftRedBorder,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppTheme.gsNavy
                                        : AppTheme.gsRed,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isActive
                                        ? AppTheme.gsNavy
                                        : AppTheme.gsRed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: Key('clinic_view_profile_${doc.id}'),
                    onPressed: onViewProfile,
                    icon: const Icon(
                      Icons.person_outline_rounded,
                      size: 15,
                      color: AppTheme.gsNavy,
                    ),
                    label: const Text(
                      'View Profile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.gsNavy,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.gsNavy),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: Key('clinic_edit_button_${doc.id}'),
                tooltip: 'Edit Doctor Details',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 19,
                  color: AppTheme.gsNavy,
                ),
                onPressed: onEdit,
              ),
              IconButton(
                key: Key('clinic_slots_button_${doc.id}'),
                tooltip: 'Update Availability Slots',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.event_available_rounded,
                  size: 19,
                  color: AppTheme.gsNavy,
                ),
                onPressed: onManageSlots,
              ),
              IconButton(
                key: Key('clinic_remove_button_${doc.id}'),
                tooltip: 'Remove Doctor from Clinic',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.person_remove_outlined,
                  size: 19,
                  color: AppTheme.gsRed,
                ),
                onPressed: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClinicDoctorInitialsAvatar extends StatelessWidget {
  final String name;

  const _ClinicDoctorInitialsAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final cleaned = name.replaceAll('Dr.', '').trim();
    final parts = cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? ''
        : parts.length == 1
            ? parts.first.substring(0, 1).toUpperCase()
            : '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
                .toUpperCase();
    return Container(
      color: _kSoftNavy,
      alignment: Alignment.center,
      child: initials.isEmpty
          ? const Icon(Icons.person_rounded, color: AppTheme.gsNavy, size: 28)
          : Text(
              initials,
              style: const TextStyle(
                color: AppTheme.gsNavy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

// =============================================================================
// CLINIC BOOKINGS TAB (SEPARATE SCREEN)
// =============================================================================

class GsHealthClinicBookingsView extends StatelessWidget {
  static const List<String> filters = [
    'All',
    'Pending',
    'Confirmed',
    'Completed',
    'Cancelled',
  ];

  final List<PatientConsultationRequest> allBookings;
  final String selectedFilter;
  final Set<String> processingBookingIds;
  final Set<String> overlappingBookingIds;
  final ValueChanged<String> onSelectFilter;
  final ValueChanged<PatientConsultationRequest> onConfirmBooking;
  final ValueChanged<PatientConsultationRequest> onCancelBooking;
  final Future<void> Function() onRefresh;

  const GsHealthClinicBookingsView({
    super.key,
    required this.allBookings,
    required this.selectedFilter,
    required this.processingBookingIds,
    required this.overlappingBookingIds,
    required this.onSelectFilter,
    required this.onConfirmBooking,
    required this.onCancelBooking,
    required this.onRefresh,
  });

  static String normalizeCategory(String rawStatus) {
    final s = rawStatus.trim().toLowerCase();
    if (s.contains('cancel') || s.contains('reject') || s.contains('declin')) {
      return 'Cancelled';
    }
    if (s.contains('complet')) {
      return 'Completed';
    }
    if (s.contains('confirm') || s.contains('accept')) {
      return 'Confirmed';
    }
    return 'Pending';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = selectedFilter == 'All'
        ? allBookings
        : allBookings
            .where((b) => normalizeCategory(b.status) == selectedFilter)
            .toList();

    return Container(
      color: _kSurfaceBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All visits at your clinic',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMedium,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Bookings',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.gsNavy,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: filters.map((filter) {
                      final selected = filter == selectedFilter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          key: Key('clinic_bookings_filter_$filter'),
                          onTap: () => onSelectFilter(filter),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? AppTheme.gsNavy : Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: selected ? AppTheme.gsNavy : _kBorder,
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              filter,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color:
                                    selected ? Colors.white : AppTheme.gsNavy,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          if (overlappingBookingIds.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kSoftRedBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kSoftRedBorder, width: 1.2),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.gsRed,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overlapping Slot Alert Detected',
                          style: TextStyle(
                            color: AppTheme.gsRed,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Multiple patients are scheduled in the same doctor time slot.',
                          style: TextStyle(
                            color: AppTheme.textDark,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.gsNavy,
              onRefresh: onRefresh,
              child: filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        _ClinicEmptyCard(
                          icon: Icons.calendar_today_outlined,
                          title: selectedFilter == 'All'
                              ? 'No clinic bookings yet'
                              : 'No $selectedFilter bookings',
                          subtitle:
                              'Patient visits scheduled with your doctors will appear here.',
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, idx) {
                        final booking = filtered[idx];
                        return _ClinicBookingCard(
                          booking: booking,
                          isProcessing:
                              processingBookingIds.contains(booking.id),
                          hasOverlap:
                              overlappingBookingIds.contains(booking.id),
                          onConfirm: () => onConfirmBooking(booking),
                          onCancel: () => onCancelBooking(booking),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClinicBookingCard extends StatelessWidget {
  final PatientConsultationRequest booking;
  final bool isProcessing;
  final bool hasOverlap;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _ClinicBookingCard({
    required this.booking,
    required this.isProcessing,
    required this.hasOverlap,
    required this.onConfirm,
    required this.onCancel,
  });

  static String _weekdayAbbr(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[(dt.weekday - 1).clamp(0, 6)];
  }

  static String _monthAbbr(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(dt.month - 1).clamp(0, 11)];
  }

  DateTime _resolveDate() {
    final raw = (booking.confirmedDate ?? '').trim();
    if (raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return booking.submittedAt;
  }

  String _extractTimeText() {
    final raw = (booking.confirmedTimeSlot ?? '').trim();
    if (raw.isEmpty) return 'TBD';
    final match = RegExp(r'\d{1,2}:\d{2}(?:\s*[APap][Mm])?').firstMatch(raw);
    return match != null ? match.group(0)! : raw;
  }

  String _extractModeLabel() {
    final text =
        '${booking.problemCategory} ${booking.symptoms} ${booking.problemDescription} ${booking.adminNotes ?? ''}'
            .toLowerCase();
    if (text.contains('audio')) return 'AUDIO CALL';
    if (text.contains('video') || text.contains('online') || text.contains('tele')) {
      return 'ONLINE';
    }
    return 'IN-CLINIC';
  }

  @override
  Widget build(BuildContext context) {
    final category = GsHealthClinicBookingsView.normalizeCategory(booking.status);
    final dt = _resolveDate();
    final dayAbbr = _weekdayAbbr(dt);
    final dateDisplay = '$dayAbbr, ${dt.day} ${_monthAbbr(dt)}';
    final timeText = _extractTimeText();
    final doctorName = booking.displayDoctorName.trim();
    final modeLabel = _extractModeLabel();
    final rawPatient = booking.patientName.trim().isNotEmpty
        ? booking.patientName.trim()
        : 'Patient';
    final rawCategory = booking.problemCategory.trim();
    final patientHeader =
        rawCategory.isNotEmpty ? '$rawPatient • $rawCategory' : rawPatient;
    final phone = booking.patientPhone.trim();
    final subtitleText = phone.isNotEmpty ? '$dateDisplay · $phone' : dateDisplay;
    final note = booking.problemDescription.trim().isNotEmpty
        ? booking.problemDescription.trim()
        : booking.symptoms.trim();

    late final Color statusBg;
    late final Color statusFg;
    switch (category) {
      case 'Pending':
        statusBg = const Color(0xFFFEF3C7);
        statusFg = const Color(0xFF92400E);
        break;
      case 'Confirmed':
        statusBg = _kSoftNavy;
        statusFg = AppTheme.gsNavy;
        break;
      case 'Completed':
        statusBg = const Color(0xFFECFDF5);
        statusFg = AppTheme.gsNavy;
        break;
      case 'Cancelled':
      default:
        statusBg = const Color(0xFFF1F5F9);
        statusFg = AppTheme.textMedium;
        break;
    }

    return Container(
      key: Key('clinic_booking_card_${booking.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasOverlap ? AppTheme.gsRed : _kBorder,
          width: hasOverlap ? 1.5 : 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Time Pill
              Container(
                width: 70,
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: _kSoftNavy,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dayAbbr,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMedium,
                      ),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        timeText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.gsNavy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Right Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            patientHeader,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.gsNavy,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: statusFg,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textMedium,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (doctorName.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.medical_services_outlined,
                            size: 14,
                            color: AppTheme.gsNavy,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              doctorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: modeLabel == 'IN-CLINIC'
                            ? const Color(0xFFF1F5F9)
                            : _kSoftNavy,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            modeLabel == 'IN-CLINIC'
                                ? Icons.apartment_rounded
                                : Icons.call_rounded,
                            size: 12,
                            color: AppTheme.gsNavy,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            modeLabel,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.gsNavy,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '"$note"',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMedium,
                        ),
                      ),
                    ],
                    if (hasOverlap) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _kSoftRedBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kSoftRedBorder),
                        ),
                        child: const Text(
                          'Overlapping Slot Conflict with another patient',
                          style: TextStyle(
                            color: AppTheme.gsRed,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (category == 'Pending') ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  key: Key('clinic_booking_confirm_${booking.id}'),
                  onPressed: isProcessing ? null : onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gsNavy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: isProcessing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Confirm',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                ElevatedButton(
                  key: Key('clinic_booking_cancel_${booking.id}'),
                  onPressed: isProcessing ? null : onCancel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kSoftRedBg,
                    foregroundColor: AppTheme.gsRed,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: _kSoftRedBorder),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CancelClinicBookingDialog extends StatefulWidget {
  final String patientName;

  const _CancelClinicBookingDialog({required this.patientName});

  @override
  State<_CancelClinicBookingDialog> createState() =>
      _CancelClinicBookingDialogState();
}

class _CancelClinicBookingDialogState
    extends State<_CancelClinicBookingDialog> {
  final TextEditingController _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Cancel Booking',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppTheme.gsNavy,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cancel appointment for ${widget.patientName}?',
              style: const TextStyle(fontSize: 13.5, color: AppTheme.textDark),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('cancel_clinic_booking_reason_field'),
              controller: _reasonCtrl,
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep Booking'),
        ),
        ElevatedButton(
          key: const Key('confirm_cancel_clinic_booking_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.gsRed,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, _reasonCtrl.text.trim()),
          child: const Text('Confirm Cancel'),
        ),
      ],
    );
  }
}

Future<String?> showCancelClinicBookingDialog(
  BuildContext context, {
  required String patientName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CancelClinicBookingDialog(patientName: patientName),
  );
}

class _ClinicEmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ClinicEmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: _kSoftNavy,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.gsNavy, size: 24),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.gsNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CLINIC MODAL BOTTOM SHEETS (EDIT DETAILS, FEATURED, REFERRALS, ADS, PROFILE, NOTIFS)
// =============================================================================

Future<void> showEditClinicDetailsSheet({
  required BuildContext context,
  required String clinicId,
  required String initialName,
  required String initialLocation,
  required String initialCoverUrl,
  required VoidCallback onOpenDepartments,
  required VoidCallback onOpenProcedureRates,
  required Future<void> Function({
    required String name,
    required String location,
    required String coverUrl,
  }) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return _EditClinicDetailsBody(
        initialName: initialName,
        initialLocation: initialLocation,
        initialCoverUrl: initialCoverUrl,
        onOpenDepartments: () {
          Navigator.pop(ctx);
          onOpenDepartments();
        },
        onOpenProcedureRates: () {
          Navigator.pop(ctx);
          onOpenProcedureRates();
        },
        onSave: onSave,
      );
    },
  );
}

class _EditClinicDetailsBody extends StatefulWidget {
  final String initialName;
  final String initialLocation;
  final String initialCoverUrl;
  final VoidCallback onOpenDepartments;
  final VoidCallback onOpenProcedureRates;
  final Future<void> Function({
    required String name,
    required String location,
    required String coverUrl,
  }) onSave;

  const _EditClinicDetailsBody({
    required this.initialName,
    required this.initialLocation,
    required this.initialCoverUrl,
    required this.onOpenDepartments,
    required this.onOpenProcedureRates,
    required this.onSave,
  });

  @override
  State<_EditClinicDetailsBody> createState() => _EditClinicDetailsBodyState();
}

class _EditClinicDetailsBodyState extends State<_EditClinicDetailsBody> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _locCtrl;
  late final TextEditingController _coverCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _locCtrl = TextEditingController(text: widget.initialLocation);
    _coverCtrl = TextEditingController(text: widget.initialCoverUrl);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locCtrl.dispose();
    _coverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: _kBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Edit clinic details',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.gsNavy,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('edit_clinic_name_field'),
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Clinic Name *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('edit_clinic_location_field'),
              controller: _locCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Address / Location',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('edit_clinic_cover_field'),
              controller: _coverCtrl,
              decoration: InputDecoration(
                labelText: 'Cover Photo URL (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onOpenDepartments,
                    icon: const Icon(Icons.apartment_rounded, size: 16),
                    label: const Text(
                      'Departments',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.gsNavy,
                      side: const BorderSide(color: _kSoftBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onOpenProcedureRates,
                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                    label: const Text(
                      'Procedure Rates',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.gsRed,
                      side: const BorderSide(color: _kSoftRedBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('save_clinic_details_button'),
                onPressed: _isSaving
                    ? null
                    : () async {
                        final cleanName = _nameCtrl.text.trim();
                        if (cleanName.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Clinic name cannot be empty.'),
                            ),
                          );
                          return;
                        }
                        setState(() => _isSaving = true);
                        await widget.onSave(
                          name: cleanName,
                          location: _locCtrl.text.trim(),
                          coverUrl: _coverCtrl.text.trim(),
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gsNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showFeaturedClinicPlanSheet({
  required BuildContext context,
  required bool currentIsFeatured,
  required String currentPlan,
  required Future<void> Function(bool isFeatured, String plan) onUpdatePlan,
}) {
  const plans = [
    'Monthly Spotlight',
    'Quarterly Growth',
    'Annual Partner',
  ];
  String selectedPlan = plans.contains(currentPlan) ? currentPlan : plans.first;
  bool saving = false;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _kSoftRedBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.star_rounded, color: AppTheme.gsRed),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Featured Clinic Plan',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.gsNavy,
                          ),
                        ),
                        Text(
                          'Priority placement on GS HEALTH discovery',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...plans.map((p) {
                final chosen = p == selectedPlan;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => setModalState(() => selectedPlan = p),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: chosen ? _kSoftNavy : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: chosen ? AppTheme.gsNavy : _kBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            chosen
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 18,
                            color: chosen ? AppTheme.gsNavy : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              p,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.gsNavy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (currentIsFeatured) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                setModalState(() => saving = true);
                                await onUpdatePlan(false, '');
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.gsRed,
                          side: const BorderSide(color: AppTheme.gsRed),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Pause Plan',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      key: const Key('activate_featured_plan_button'),
                      onPressed: saving
                          ? null
                          : () async {
                              setModalState(() => saving = true);
                              await onUpdatePlan(true, selectedPlan);
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gsNavy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        currentIsFeatured
                            ? 'Update Plan'
                            : 'Activate Featured Plan',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showAdvertiseOnGsHealthSheet({
  required BuildContext context,
  required String clinicName,
  required Future<void> Function({
    required String headline,
    required String audience,
    required String notes,
  }) onSubmit,
}) {
  final headlineCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  String audience = 'Patients & Dentists';
  bool submitting = false;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _kSoftNavy,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.campaign_outlined,
                      color: AppTheme.gsRed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Advertise on GS HEALTH',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.gsNavy,
                          ),
                        ),
                        Text(
                          'Sponsored banner request for ${clinicName.trim().isNotEmpty ? clinicName.trim() : 'your clinic'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('advertise_headline_field'),
                controller: headlineCtrl,
                decoration: InputDecoration(
                  labelText: 'Campaign Headline *',
                  hintText: 'e.g. Digital Smile Design Camp',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Target Audience',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.gsNavy,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: ['Patients', 'Dentists', 'Patients & Dentists'].map((a) {
                  final sel = audience == a;
                  return ChoiceChip(
                    label: Text(a),
                    selected: sel,
                    selectedColor: AppTheme.gsNavy,
                    labelStyle: TextStyle(
                      color: sel ? Colors.white : AppTheme.gsNavy,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => setModalState(() => audience = a),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Offer / Notes (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('submit_advertise_request_button'),
                  onPressed: submitting
                      ? null
                      : () async {
                          final headline = headlineCtrl.text.trim();
                          if (headline.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a campaign headline.'),
                              ),
                            );
                            return;
                          }
                          setModalState(() => submitting = true);
                          await onSubmit(
                            headline: headline,
                            audience: audience,
                            notes: notesCtrl.text.trim(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gsRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit Banner Request',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showClinicReferralsSheet({
  required BuildContext context,
  required String clinicName,
  required List<PatientReferral> referrals,
  required VoidCallback onOpenReferralDirectory,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _kBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Patient referrals',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.gsNavy,
                          ),
                        ),
                        Text(
                          clinicName.trim().isNotEmpty
                              ? 'Referred to $clinicName'
                              : 'Patients referred by dentists',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      onOpenReferralDirectory();
                    },
                    child: const Text(
                      'All Tracker',
                      style: TextStyle(
                        color: AppTheme.gsNavy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (referrals.isEmpty)
                const _ClinicEmptyCard(
                  icon: Icons.medical_information_outlined,
                  title: 'No referrals received yet',
                  subtitle:
                      'When dentists refer patients to your doctors or clinic, their notes and case details will appear here.',
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: referrals.length,
                    itemBuilder: (_, idx) {
                      final ref = referrals[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _kSurfaceBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    ref.referredPatientName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.gsNavy,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _kSoftNavy,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    ref.status,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.gsNavy,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${ref.doctorName} · ${ref.requiredSpecialist}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                            if (ref.clinicalComplaint.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                ref.clinicalComplaint,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMedium,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showClinicNotificationsSheet({
  required BuildContext context,
  required List<AppNotificationModel> notifications,
  required ValueChanged<String> onMarkRead,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Clinic Notifications',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.gsNavy,
                ),
              ),
              const SizedBox(height: 12),
              if (notifications.isEmpty)
                const _ClinicEmptyCard(
                  icon: Icons.notifications_none_rounded,
                  title: 'No new notifications',
                  subtitle: 'Clinic booking and referral updates appear here.',
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: notifications.length,
                    itemBuilder: (_, idx) {
                      final n = notifications[idx];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: n.isRead ? _kSoftNavy : _kSoftRedBg,
                          child: Icon(
                            Icons.notifications_active_outlined,
                            size: 18,
                            color: n.isRead ? AppTheme.gsNavy : AppTheme.gsRed,
                          ),
                        ),
                        title: Text(
                          n.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: AppTheme.gsNavy,
                          ),
                        ),
                        subtitle: Text(
                          n.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => onMarkRead(n.id),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showClinicProfileSheet({
  required BuildContext context,
  required String clinicName,
  required String location,
  required String phone,
  required String email,
  required int doctorCount,
  required int bookingsCount,
  required VoidCallback onEditDetails,
  required VoidCallback onOpenDepartments,
  required VoidCallback onOpenProcedureRates,
  required VoidCallback onOpenFeaturedPlan,
  required Future<void> Function() onSignOut,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _kSoftNavy,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kSoftBorder),
                  ),
                  child: const Icon(
                    Icons.apartment_rounded,
                    color: AppTheme.gsNavy,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clinicName.trim().isNotEmpty
                            ? clinicName.trim()
                            : 'Clinic Workspace',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.gsNavy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kSoftRedBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Clinic Partner',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.gsRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (location.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                location.trim(),
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textMedium),
              ),
            ],
            if (phone.trim().isNotEmpty || email.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                [if (phone.trim().isNotEmpty) phone.trim(), if (email.trim().isNotEmpty) email.trim()].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '$doctorCount attached doctor(s) · $bookingsCount clinic booking(s)',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.gsNavy,
              ),
            ),
            const Divider(height: 22),
            _ProfileMenuTile(
              icon: Icons.edit_outlined,
              label: 'Edit Clinic Details',
              onTap: () {
                Navigator.pop(ctx);
                onEditDetails();
              },
            ),
            _ProfileMenuTile(
              icon: Icons.apartment_rounded,
              label: 'Departments & Specialties',
              onTap: () {
                Navigator.pop(ctx);
                onOpenDepartments();
              },
            ),
            _ProfileMenuTile(
              icon: Icons.receipt_long_rounded,
              label: 'Procedure Rates & Services',
              onTap: () {
                Navigator.pop(ctx);
                onOpenProcedureRates();
              },
            ),
            _ProfileMenuTile(
              icon: Icons.star_outline_rounded,
              label: 'Featured Plan',
              onTap: () {
                Navigator.pop(ctx);
                onOpenFeaturedPlan();
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('clinic_sign_out_button'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await onSignOut();
                },
                icon: const Icon(Icons.logout_rounded, color: AppTheme.gsRed),
                label: const Text(
                  'Sign out',
                  style: TextStyle(
                    color: AppTheme.gsRed,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kSoftRedBorder),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.gsNavy, size: 20),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.gsNavy,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
      onTap: onTap,
    );
  }
}
