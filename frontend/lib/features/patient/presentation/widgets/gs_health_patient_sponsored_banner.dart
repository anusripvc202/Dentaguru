import 'package:flutter/material.dart';

import '../../../../core/models/medical_specialty_model.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../screens/ai_triage_screen.dart';
import '../screens/find_doctors_screen.dart';

enum GsSponsoredDestination {
  findDoctorsAll,
  findDoctorsSpecialty,
  aiTriage,
}

class GsHealthSponsoredAdItem {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final GsSponsoredDestination destination;
  final String? targetSpecialty;

  const GsHealthSponsoredAdItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.destination,
    this.targetSpecialty,
  });
}

class GsHealthPatientSponsoredBanner extends StatefulWidget {
  final List<MedicalSpecialtyModel> activeSpecialties;
  final List<DoctorModel> availableDoctors;
  final void Function(GsHealthSponsoredAdItem ad)? onAdTap;

  const GsHealthPatientSponsoredBanner({
    super.key,
    required this.activeSpecialties,
    required this.availableDoctors,
    this.onAdTap,
  });

  /// Builds GS HEALTH multi-specialty advertisements dynamically from active specialties
  /// and available healthcare services, excluding dental-only advertisements.
  static List<GsHealthSponsoredAdItem> buildDynamicAds({
    required List<MedicalSpecialtyModel> activeSpecialties,
    required List<DoctorModel> availableDoctors,
  }) {
    final activeList = activeSpecialties.where((s) => s.isActive).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    final nonDentalSpecialties = activeList
        .where((s) => !MedicalSpecialtyModel.isDentalSpecialty(s.name))
        .toList();

    final hasDoctorInventory = availableDoctors.isNotEmpty;
    final availableNonDentalSpecs = <MedicalSpecialtyModel>[];
    for (final spec in nonDentalSpecialties) {
      if (!hasDoctorInventory) {
        availableNonDentalSpecs.add(spec);
      } else {
        final hasAvailableDoc = availableDoctors.any(
          (doc) =>
              doc.isAvailable &&
              MedicalSpecialtyModel.matchesSpecialtyFilter(
                doc.specialty,
                spec.name,
                specialties: activeList,
              ),
        );
        if (hasAvailableDoc) {
          availableNonDentalSpecs.add(spec);
        }
      }
    }

    final String overviewDesc;
    if (availableNonDentalSpecs.isNotEmpty) {
      final previewNames = availableNonDentalSpecs
          .take(3)
          .map((s) => s.name)
          .join(', ');
      overviewDesc = 'Consult verified doctors across $previewNames & more';
    } else {
      overviewDesc = 'Multi-specialty consultations, AI triage & preventive care';
    }

    final items = <GsHealthSponsoredAdItem>[
      GsHealthSponsoredAdItem(
        id: 'gs-complete-care',
        title: 'GS HEALTH',
        subtitle: 'COMPLETE HEALTHCARE SOLUTIONS',
        description: overviewDesc,
        icon: Icons.health_and_safety_rounded,
        destination: GsSponsoredDestination.findDoctorsAll,
      ),
      const GsHealthSponsoredAdItem(
        id: 'gs-digital-care',
        title: 'GS HEALTH DIGITAL CARE',
        subtitle: 'DIGITAL HEALTHCARE SERVICES',
        description: '24/7 AI health triage, health locker & preventive checkups',
        icon: Icons.auto_awesome_rounded,
        destination: GsSponsoredDestination.aiTriage,
      ),
    ];

    for (final spec in availableNonDentalSpecs) {
      items.add(_buildSpecialtyAd(spec));
    }

    return items;
  }

  static GsHealthSponsoredAdItem _buildSpecialtyAd(MedicalSpecialtyModel spec) {
    final name = spec.name.trim();
    final lower = name.toLowerCase();

    if (lower == 'general medicine' || lower.contains('internal medicine')) {
      return GsHealthSponsoredAdItem(
        id: 'gs-spec-${spec.code.toLowerCase()}',
        title: 'GS HEALTH PRIMARY CARE',
        subtitle: 'GENERAL HEALTH CONSULTATIONS',
        description: 'Fever, preventive health checkups & family care doctors',
        icon: Icons.medical_services_rounded,
        destination: GsSponsoredDestination.findDoctorsSpecialty,
        targetSpecialty: name,
      );
    }
    if (lower.contains('cardio')) {
      return GsHealthSponsoredAdItem(
        id: 'gs-spec-${spec.code.toLowerCase()}',
        title: 'GS HEALTH CARDIOLOGY',
        subtitle: 'CARDIOLOGY CONSULTATIONS',
        description: 'Heart health checkups, BP care & cardiac specialists',
        icon: Icons.favorite_rounded,
        destination: GsSponsoredDestination.findDoctorsSpecialty,
        targetSpecialty: name,
      );
    }
    if (lower.contains('derma')) {
      return GsHealthSponsoredAdItem(
        id: 'gs-spec-${spec.code.toLowerCase()}',
        title: 'GS HEALTH DERMATOLOGY',
        subtitle: 'DERMATOLOGY CONSULTATIONS',
        description: 'Skin allergies, acne, rashes & hair care specialists',
        icon: Icons.healing_rounded,
        destination: GsSponsoredDestination.findDoctorsSpecialty,
        targetSpecialty: name,
      );
    }
    if (lower.contains('ortho')) {
      return GsHealthSponsoredAdItem(
        id: 'gs-spec-${spec.code.toLowerCase()}',
        title: 'GS HEALTH ORTHOPEDICS',
        subtitle: 'ORTHOPEDIC CARE',
        description: 'Joint pain, back care, bone health & mobility specialists',
        icon: Icons.accessibility_new_rounded,
        destination: GsSponsoredDestination.findDoctorsSpecialty,
        targetSpecialty: name,
      );
    }
    if (lower.contains('gynec') || lower.contains('obstet')) {
      return GsHealthSponsoredAdItem(
        id: 'gs-spec-${spec.code.toLowerCase()}',
        title: 'GS HEALTH WOMEN\'S CARE',
        subtitle: 'WOMEN\'S HEALTHCARE',
        description: 'Gynecology, maternity wellness & women\'s specialists',
        icon: Icons.volunteer_activism_rounded,
        destination: GsSponsoredDestination.findDoctorsSpecialty,
        targetSpecialty: name,
      );
    }
    if (lower.contains('pedia')) {
      return GsHealthSponsoredAdItem(
        id: 'gs-spec-${spec.code.toLowerCase()}',
        title: 'GS HEALTH PEDIATRICS',
        subtitle: 'CHILD HEALTHCARE',
        description: 'Child health checkups, nutrition & pediatric specialists',
        icon: Icons.child_care_rounded,
        destination: GsSponsoredDestination.findDoctorsSpecialty,
        targetSpecialty: name,
      );
    }

    final cleanDesc = spec.description.trim().isNotEmpty
        ? spec.description.trim()
        : 'Book verified $name consultations across GS HEALTH';

    return GsHealthSponsoredAdItem(
      id: 'gs-spec-${spec.code.toLowerCase()}',
      title: 'GS HEALTH ${name.toUpperCase()}',
      subtitle: '${name.toUpperCase()} CONSULTATIONS',
      description: cleanDesc,
      icon: _iconForSpecialty(lower, spec.iconName),
      destination: GsSponsoredDestination.findDoctorsSpecialty,
      targetSpecialty: name,
    );
  }

  static IconData _iconForSpecialty(String lowerName, String iconName) {
    if (lowerName.contains('neuro') || iconName == 'psychology') {
      return Icons.psychology_rounded;
    }
    if (lowerName.contains('ophthal') || lowerName.contains('eye')) {
      return Icons.visibility_rounded;
    }
    if (lowerName == 'ent' || iconName == 'hearing') {
      return Icons.hearing_rounded;
    }
    if (lowerName.contains('pulmo') || iconName == 'air') {
      return Icons.air_rounded;
    }
    if (lowerName.contains('physio')) {
      return Icons.directions_walk_rounded;
    }
    return Icons.local_hospital_rounded;
  }

  @override
  State<GsHealthPatientSponsoredBanner> createState() =>
      _GsHealthPatientSponsoredBannerState();
}

class _GsHealthPatientSponsoredBannerState
    extends State<GsHealthPatientSponsoredBanner> {
  int _activeIndex = 0;

  void _openAdDestination(BuildContext context, GsHealthSponsoredAdItem ad) {
    if (widget.onAdTap != null) {
      widget.onAdTap!(ad);
      return;
    }

    if (ad.destination == GsSponsoredDestination.aiTriage) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AiTriageScreen()),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FindDoctorsScreen(
          initialSpecialty:
              ad.destination == GsSponsoredDestination.findDoctorsSpecialty
                  ? (ad.targetSpecialty ?? 'All')
                  : 'All',
        ),
      ),
    );
  }

  void _nextAd(int total) {
    if (total <= 1) return;
    setState(() {
      _activeIndex = (_activeIndex + 1) % total;
    });
  }

  void _previousAd(int total) {
    if (total <= 1) return;
    setState(() {
      _activeIndex = (_activeIndex - 1 + total) % total;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ads = GsHealthPatientSponsoredBanner.buildDynamicAds(
      activeSpecialties: widget.activeSpecialties,
      availableDoctors: widget.availableDoctors,
    );
    final safeIndex = _activeIndex >= ads.length ? 0 : _activeIndex;
    final ad = ads[safeIndex];

    return GestureDetector(
      onHorizontalDragEnd: ads.length > 1
          ? (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -150) {
                _nextAd(ads.length);
              } else if (v > 150) {
                _previousAd(ads.length);
              }
            }
          : null,
      child: InkWell(
        key: const Key('patient_sponsored_banner'),
        onTap: () => _openAdDestination(context, ad),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.gsNavy.withValues(alpha: 0.08),
                AppTheme.brandOrange.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(
              color: AppTheme.gsNavy.withValues(alpha: 0.20),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.gsNavy.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.brandOrange,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'SPONSORED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  if (ads.length > 1)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...List.generate(
                          ads.length > 5 ? 5 : ads.length,
                          (i) {
                            final activeDot = i == (safeIndex % (ads.length > 5 ? 5 : ads.length));
                            return Container(
                              key: Key('patient_sponsored_dot_$i'),
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              width: activeDot ? 14 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: activeDot
                                    ? AppTheme.gsNavy
                                    : AppTheme.brandOrange.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          key: const Key('patient_sponsored_next_btn'),
                          onTap: () => _nextAd(ads.length),
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: AppTheme.gsNavy,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.brandOrange,
                        width: 1.4,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        ad.icon,
                        color: AppTheme.gsNavy,
                        size: 25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ad.title,
                          key: const Key('patient_sponsored_title'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.gsNavy,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          ad.subtitle,
                          key: const Key('patient_sponsored_subtitle'),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.brandOrange,
                            letterSpacing: 0.8,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      ad.description,
                      key: const Key('patient_sponsored_description'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.gsNavy,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.open_in_new_rounded,
                    color: AppTheme.brandOrange,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
