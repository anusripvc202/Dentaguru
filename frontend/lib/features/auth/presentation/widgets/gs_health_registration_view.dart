import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';

/// Role enum for GS HEALTH authentication and registration.
enum UserRole { patient, dentist, clinic, admin }

/// Canonical GS HEALTH Preferred Languages list matching Patient Profile.
const List<String> kGsHealthLanguages = <String>[
  'English',
  'Hindi',
  'Marathi',
  'Tamil',
  'Telugu',
  'Kannada',
  'Malayalam',
  'Bengali',
  'Gujarati',
  'Punjabi',
  'Urdu',
  'Odia',
];

/// Patient-friendly chip labels for stored dental specialty values.
/// The stored value (e.g. 'General Dentistry') is what is submitted to the
/// backend, so existing specialty matching keeps working unchanged.
const Map<String, String> _kSpecialtyDisplayLabels = <String, String>{
  'general dentistry': 'General Dentist',
  'orthodontics': 'Orthodontist',
  'endodontics': 'Endodontist',
  'periodontics': 'Periodontist',
  'pediatric dentistry': 'Pediatric Dentist',
  'oral & maxillofacial surgery': 'Oral Surgeon',
  'prosthodontics': 'Prosthodontist',
};

String gsSpecialtyDisplayLabel(String specialty) =>
    _kSpecialtyDisplayLabels[specialty.trim().toLowerCase()] ?? specialty;

/// A registered clinic a dentist may associate with during registration.
class GsRegistrationClinicOption {
  final String id;
  final String name;
  final String location;

  const GsRegistrationClinicOption({
    required this.id,
    required this.name,
    required this.location,
  });
}

class GsHealthRegistrationView extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final UserRole selectedRole;
  final bool isAuthorizedAdminPortal;
  final bool isOtpVerified;
  final String? verifiedPhone;
  final bool isRegistering;
  final TextEditingController nameController;
  final TextEditingController cityController;
  final TextEditingController pincodeController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController locationController;
  final TextEditingController licenseNoController;
  final TextEditingController qualificationController;
  final TextEditingController clinicNameController;
  final TextEditingController clinicAddressController;
  final TextEditingController experienceController;
  final TextEditingController adminEmployeeIdController;
  final TextEditingController adminDeptController;
  final String selectedAdminRoleType;
  final String? selectedSpecialty;
  final List<String> specialtyOptions;
  final Set<String> selectedLanguages;
  final double? selectedLatitude;
  final double? selectedLongitude;
  final String? selectedMapLocationName;
  final Uint8List? pickedImageBytes;
  final String? pickedImageName;
  final Widget Function() mobileOtpSectionBuilder;
  final ValueChanged<UserRole> onRoleSelected;
  final ValueChanged<String> onLanguageToggled;
  final ValueChanged<String> onAdminRoleTypeChanged;
  final ValueChanged<String> onSpecialtyChanged;
  final VoidCallback onPickImage;
  final VoidCallback onOpenMapPicker;
  final VoidCallback onContinuePressed;
  final VoidCallback onUseAnotherNumber;
  final VoidCallback onOpenAdminSignIn;
  final List<GsRegistrationClinicOption> clinicOptions;
  final ValueChanged<GsRegistrationClinicOption?>? onClinicSelected;

  const GsHealthRegistrationView({
    super.key,
    required this.formKey,
    required this.selectedRole,
    required this.isAuthorizedAdminPortal,
    required this.isOtpVerified,
    required this.verifiedPhone,
    required this.isRegistering,
    required this.nameController,
    required this.cityController,
    required this.pincodeController,
    required this.emailController,
    required this.phoneController,
    required this.locationController,
    required this.licenseNoController,
    required this.qualificationController,
    required this.clinicNameController,
    required this.clinicAddressController,
    required this.experienceController,
    required this.adminEmployeeIdController,
    required this.adminDeptController,
    required this.selectedAdminRoleType,
    required this.selectedSpecialty,
    required this.specialtyOptions,
    required this.selectedLanguages,
    required this.selectedLatitude,
    required this.selectedLongitude,
    required this.selectedMapLocationName,
    required this.pickedImageBytes,
    required this.pickedImageName,
    required this.mobileOtpSectionBuilder,
    required this.onRoleSelected,
    required this.onLanguageToggled,
    required this.onAdminRoleTypeChanged,
    required this.onSpecialtyChanged,
    required this.onPickImage,
    required this.onOpenMapPicker,
    required this.onContinuePressed,
    required this.onUseAnotherNumber,
    required this.onOpenAdminSignIn,
    this.clinicOptions = const <GsRegistrationClinicOption>[],
    this.onClinicSelected,
  });

  bool get _isRestrictedAdminSelected =>
      selectedRole == UserRole.admin && !isAuthorizedAdminPortal;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    final hasVerifiedPhone =
        isOtpVerified && verifiedPhone != null && verifiedPhone!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPad = constraints.maxWidth < 360 ? 16.0 : 22.0;
            return SingleChildScrollView(
              key: const Key('registration_scroll_view'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                horizontalPad,
                16,
                horizontalPad,
                bottomSafe + 28,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: GsHealthLogo(
                            key: Key('reg_gs_health_logo'),
                            height: 52,
                            alignment: Alignment.center,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildStatusLine(hasVerifiedPhone),
                        const SizedBox(height: 8),
                        _buildHeadline(),
                        const SizedBox(height: 8),
                        Text(
                          'Tell us who you are so we can set things up.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF475569),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _buildRoleGrid(),
                        const SizedBox(height: 24),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _buildRoleSection(context),
                        ),
                        const SizedBox(height: 26),
                        _buildBottomActions(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusLine(bool hasVerifiedPhone) {
    if (hasVerifiedPhone) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.verified_user_rounded,
                size: 15,
                color: AppTheme.gsRed,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'Signed in as +91${verifiedPhone!.trim()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.gsNavy,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppTheme.gsRed,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Mobile OTP verification required before saving',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475569),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeadline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Welcome to\n',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.gsNavy,
                  height: 1.15,
                  letterSpacing: -0.6,
                ),
              ),
              TextSpan(
                text: 'GS ',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.gsNavy,
                  height: 1.15,
                  letterSpacing: -0.6,
                ),
              ),
              TextSpan(
                text: 'HEALTH',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.gsRed,
                  height: 1.15,
                  letterSpacing: -0.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              colors: [AppTheme.gsNavy, AppTheme.gsRed],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleGrid() {
    return IntrinsicHeight(
      key: const Key('reg_role_grid'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildRoleCard(
              cardKey: const Key('reg_role_patient'),
              role: UserRole.patient,
              title: 'Patient',
              subtitle: 'Get triage & book visits',
              icon: Icons.person_rounded,
              unselectedTint: AppTheme.gsNavy,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildRoleCard(
              cardKey: const Key('reg_role_dentist'),
              role: UserRole.dentist,
              title: 'Dentist',
              subtitle: 'Manage your patients',
              icon: Icons.medical_services_rounded,
              unselectedTint: AppTheme.gsRed,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildRoleCard(
              cardKey: const Key('reg_role_clinic'),
              role: UserRole.clinic,
              title: 'Clinic',
              subtitle: 'Run your practice',
              icon: Icons.local_hospital_rounded,
              unselectedTint: AppTheme.gsNavy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleCard({
    required Key cardKey,
    required UserRole role,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color unselectedTint,
  }) {
    final bool isSelected = selectedRole == role;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$title role card',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: cardKey,
          borderRadius: BorderRadius.circular(16),
          onTap: () => onRoleSelected(role),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFEFF4FA) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppTheme.gsNavy : const Color(0xFFE2E8F0),
                width: isSelected ? 2.0 : 1.2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppTheme.gsNavy.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : const [
                      BoxShadow(
                        color: Color(0x060F172A),
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.gsRed
                            : unselectedTint.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        size: 19,
                        color: isSelected ? Colors.white : unselectedTint,
                      ),
                    ),
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppTheme.gsNavy,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? AppTheme.gsNavy : const Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF475569),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSection(BuildContext context) {
    switch (selectedRole) {
      case UserRole.patient:
        return _buildPatientFormSection();
      case UserRole.dentist:
        return _buildDentistFormSection();
      case UserRole.clinic:
        return _buildClinicFormSection();
      case UserRole.admin:
        return _buildPatientFormSection();
    }
  }

  Widget _buildPatientFormSection() {
    return Column(
      key: const ValueKey('patient_form_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel('FULL NAME'),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('reg_full_name_field'),
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          validator: (val) =>
              (val == null || val.trim().isEmpty) ? 'Please enter your name' : null,
          decoration: _fieldDecoration(hintText: 'e.g. Riya Sharma'),
        ),
        const SizedBox(height: 18),
        _buildFieldLabel('CITY'),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('reg_city_field'),
          controller: cityController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          validator: (_) => null,
          decoration: _fieldDecoration(hintText: 'e.g. Mumbai'),
        ),
        const SizedBox(height: 18),
        _buildFieldLabel('PREFERRED LANGUAGES'),
        const SizedBox(height: 10),
        _buildPreferredLanguagesWrap(),
        if (!isOtpVerified) ...[
          const SizedBox(height: 20),
          mobileOtpSectionBuilder(),
        ],
      ],
    );
  }

  Widget _buildDentistFormSection() {
    final String effectiveSpecialty = (selectedSpecialty != null &&
            specialtyOptions.contains(selectedSpecialty))
        ? selectedSpecialty!
        : (specialtyOptions.isNotEmpty ? specialtyOptions.first : '');

    return Column(
      key: const ValueKey('dentist_form_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Full Name
        _buildFieldLabel('FULL NAME'),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('reg_full_name_field'),
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          validator: (val) =>
              (val == null || val.trim().isEmpty) ? 'Please enter your name' : null,
          decoration: _fieldDecoration(hintText: 'e.g. Riya Sharma'),
        ),
        const SizedBox(height: 18),

        // 2. City
        _buildFieldLabel('CITY'),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('reg_city_field'),
          controller: cityController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          validator: (_) => null,
          decoration: _fieldDecoration(hintText: 'e.g. Mumbai'),
        ),
        const SizedBox(height: 18),

        // 3. Languages You Consult In
        _buildFieldLabel('LANGUAGES YOU CONSULT IN'),
        const SizedBox(height: 10),
        _buildPreferredLanguagesWrap(),
        const SizedBox(height: 20),

        // 4. Speciality
        _buildFieldLabel('SPECIALITY'),
        const SizedBox(height: 10),
        SingleChildScrollView(
          key: const Key('reg_specialty_scroll'),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              for (int i = 0; i < specialtyOptions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _buildSelectableChip(
                  key: Key('reg_specialty_chip_${specialtyOptions[i]}'),
                  label: gsSpecialtyDisplayLabel(specialtyOptions[i]),
                  selected: specialtyOptions[i] == effectiveSpecialty,
                  onTap: () => onSpecialtyChanged(specialtyOptions[i]),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 5. Qualification
        _buildFieldLabel('QUALIFICATION'),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('reg_qualification_field'),
          controller: qualificationController,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          decoration: _fieldDecoration(hintText: 'e.g. BDS, MDS'),
        ),
        const SizedBox(height: 18),

        // 6. Years of Practice
        _buildFieldLabel('YEARS OF PRACTICE'),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('reg_experience_field'),
          controller: experienceController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          validator: (val) {
            final v = (val ?? '').trim();
            if (v.isEmpty) return null;
            final years = int.tryParse(v);
            if (years == null || years > 70) {
              return 'Enter valid years of practice (0-70)';
            }
            return null;
          },
          decoration: _fieldDecoration(hintText: 'e.g. 6'),
        ),
        const SizedBox(height: 20),

        // 7. Clinic (Optional)
        _buildFieldLabel('CLINIC (OPTIONAL)'),
        const SizedBox(height: 10),
        _buildClinicSelector(),

        if (!isOtpVerified) ...[
          const SizedBox(height: 20),
          mobileOtpSectionBuilder(),
        ],

        // 8. Review information
        const SizedBox(height: 20),
        _buildDentistReviewNote(),
      ],
    );
  }

  Widget _buildClinicSelector() {
    final String currentClinic = clinicNameController.text.trim().toLowerCase();
    final bool isIndependent = currentClinic.isEmpty;

    return SingleChildScrollView(
      key: const Key('reg_clinic_scroll'),
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildSelectableChip(
            key: const Key('reg_clinic_chip_independent'),
            label: 'Independent',
            selected: isIndependent,
            onTap: () => onClinicSelected?.call(null),
          ),
          for (final clinic in clinicOptions) ...[
            const SizedBox(width: 8),
            _buildSelectableChip(
              key: Key('reg_clinic_chip_${clinic.id.isNotEmpty ? clinic.id : clinic.name}'),
              label: clinic.name,
              selected: !isIndependent && clinic.name.trim().toLowerCase() == currentClinic,
              onTap: () => onClinicSelected?.call(clinic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectableChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppTheme.gsNavy : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selected ? AppTheme.gsNavy : const Color(0xFFDCE3EC),
                width: 1.2,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDentistReviewNote() {
    return Container(
      key: const Key('reg_dentist_review_note'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.verified_user_rounded, size: 18, color: AppTheme.gsRed),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'New dentist profiles are reviewed by GS HEALTH before they appear to patients.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicFormSection() {
    return Column(
      key: const ValueKey('clinic_form_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Full Name
        _buildFieldLabel('FULL NAME'),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('reg_full_name_field'),
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          validator: (val) =>
              (val == null || val.trim().isEmpty) ? 'Please enter your name' : null,
          decoration: _fieldDecoration(hintText: 'e.g. Riya Sharma'),
        ),
        const SizedBox(height: 18),

        // 2. City
        _buildFieldLabel('CITY'),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('reg_city_field'),
          controller: cityController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          validator: (_) => null,
          decoration: _fieldDecoration(hintText: 'e.g. Mumbai'),
        ),
        const SizedBox(height: 18),

        // 3. Clinic / Hospital Name
        _buildFieldLabel('CLINIC / HOSPITAL NAME'),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('reg_clinic_name_field'),
          controller: clinicNameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          validator: (val) => (val == null || val.trim().isEmpty)
              ? 'Please enter clinic name'
              : null,
          decoration: _fieldDecoration(
            hintText: 'e.g. Smile Studio',
          ),
        ),
        const SizedBox(height: 18),

        // 4. Clinic Address
        _buildFieldLabel('CLINIC ADDRESS'),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('reg_clinic_address_field'),
          controller: clinicAddressController,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          validator: (_) => null,
          decoration: _fieldDecoration(
            hintText: 'Street, area',
          ),
        ),
        const SizedBox(height: 18),

        // 5. Pincode
        _buildFieldLabel('PINCODE'),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('reg_pincode_field'),
          controller: pincodeController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          validator: (val) {
            if (val == null || val.trim().isEmpty) return null;
            if (!RegExp(r'^\d{6}$').hasMatch(val.trim())) {
              return '6-digit PIN';
            }
            return null;
          },
          decoration: _fieldDecoration(hintText: 'e.g. 400050'),
        ),

        if (!isOtpVerified) ...[
          const SizedBox(height: 20),
          mobileOtpSectionBuilder(),
        ],
      ],
    );
  }

  Widget _buildPreferredLanguagesWrap() {
    return Wrap(
      key: const Key('reg_languages_wrap'),
      spacing: 8,
      runSpacing: 9,
      children: kGsHealthLanguages.map((lang) {
        final bool isSelected = selectedLanguages.contains(lang);
        return Semantics(
          button: true,
          selected: isSelected,
          label: '$lang language option',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('reg_lang_chip_$lang'),
              borderRadius: BorderRadius.circular(24),
              onTap: () => onLanguageToggled(lang),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.gsRed : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.gsRed
                        : const Color(0xFFDCE3EC),
                    width: 1.2,
                  ),
                ),
                child: Text(
                  lang,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAddressFieldWithMap({
    required String label,
    required TextEditingController controller,
    required String hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: _fieldTextStyle(),
          decoration: _fieldDecoration(
            hintText: hintText,
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: onOpenMapPicker,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.gsNavy.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.map_rounded,
                        size: 14,
                        color: AppTheme.gsRed,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Map',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.gsNavy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (selectedLatitude != null && selectedLongitude != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.gsNavy.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_pin,
                  size: 14,
                  color: AppTheme.gsRed,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Map Pin: ${selectedMapLocationName ?? 'Pinned Location'} (${selectedLatitude!.toStringAsFixed(4)}, ${selectedLongitude!.toStringAsFixed(4)})',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.gsNavy,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }


  Widget _buildBottomActions() {
    final bool canContinue = !isRegistering && !_isRestrictedAdminSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 54,
          child: ElevatedButton(
            key: const Key('reg_continue_button'),
            onPressed: canContinue ? onContinuePressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gsNavy,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE2E8F0),
              disabledForegroundColor: const Color(0xFF94A3B8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: isRegistering
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.2,
                    ),
                  )
                : const Text('Continue'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: OutlinedButton(
            key: const Key('reg_use_another_number_button'),
            onPressed: isRegistering ? null : onUseAnotherNumber,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.gsNavy,
              side: const BorderSide(color: Color(0xFFD5DCE6), width: 1.3),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.phone_outlined, size: 17, color: AppTheme.gsRed),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Use another number',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
        color: const Color(0xFF475569),
      ),
    );
  }

  TextStyle _fieldTextStyle() {
    return GoogleFonts.plusJakartaSans(
      fontSize: 15.5,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF0F172A),
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.plusJakartaSans(
        fontSize: 15.5,
        fontWeight: FontWeight.w400,
        color: const Color(0xFF94A3B8),
      ),
      filled: true,
      fillColor: const Color(0xFFF3F5F8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.gsNavy, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.gsRed, width: 1.3),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.gsRed, width: 1.8),
      ),
    );
  }
}
