import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/clinic_directions_helper.dart';
import '../../../../core/widgets/map_location_picker_dialog.dart';
import '../../../patient/presentation/widgets/referred_patients_sheet.dart';
import 'dentist_timeline.dart';

typedef DentistProfileScreen = DoctorProfileScreen;

class DoctorProfileScreen extends StatefulWidget {
  const DoctorProfileScreen({super.key});

  @visibleForTesting
  static Future<({Uint8List bytes, String name})?> Function(ImageSource source)?
      debugPickProfileImageOverride;

  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  final PatientProblemService _patientService = PatientProblemService();

  static const List<String> availableLanguages = [
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

  static const String clinicalHelplineNumber = '+911800200100';

  bool _isSavingLanguages = false;

  @override
  void initState() {
    super.initState();
    _patientService.addListener(_onServiceChanged);
    _patientService.syncAllDataFromApi();
    _patientService.syncDoctorReferralsFromApi();
  }

  @override
  void dispose() {
    _patientService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  DoctorModel _resolveCurrentDoctor() {
    final cur = _patientService.currentDoctor;
    if (cur != null) return cur;

    User? supaUser;
    try {
      supaUser = Supabase.instance.client.auth.currentUser;
    } catch (_) {}

    final session = SessionService().currentSession;
    final fallbackId = supaUser?.id ?? session?.userId ?? '';
    final fallbackName = (supaUser?.userMetadata?['name'] ?? session?.name ?? 'Doctor').toString().trim();
    final fallbackPhone = (supaUser?.phone ?? session?.phone ?? '').toString().trim();
    final fallbackEmail = (supaUser?.email ?? session?.email ?? '').toString().trim();

    // Check if doc exists in allDoctors
    for (final d in _patientService.allDoctors) {
      if (fallbackId.isNotEmpty && (d.id == fallbackId || (d.userId.isNotEmpty && d.userId == fallbackId))) {
        return d;
      }
      if (d.phone.isNotEmpty && fallbackPhone.isNotEmpty && d.phone.replaceAll(RegExp(r'\D'), '') == fallbackPhone.replaceAll(RegExp(r'\D'), '')) {
        return d;
      }
    }

    final meta = supaUser?.userMetadata ?? const {};
    final fallbackSpecialty = (meta['specialty'] ?? meta['speciality'] ?? 'General Medicine').toString().trim();
    final fallbackQual = (meta['qualification'] ?? meta['qualifications'] ?? '').toString().trim();

    return DoctorModel(
      id: fallbackId,
      userId: fallbackId,
      name: fallbackName.isNotEmpty ? fallbackName : 'Doctor',
      specialty: fallbackSpecialty.isNotEmpty ? fallbackSpecialty : 'General Medicine',
      qualification: fallbackQual,
      experienceYears: int.tryParse((meta['experienceYears'] ?? meta['experience_years'] ?? '0').toString()) ?? 0,
      rating: 0.0,
      reviewCount: 0,
      clinicName: (meta['clinicName'] ?? meta['clinic_name'] ?? '').toString(),
      phone: fallbackPhone,
      email: fallbackEmail,
      status: 'Available',
      verificationStatus: 'VERIFIED',
      nextAvailableSlots: const [],
      consultationFee: (meta['consultationFee'] ?? '').toString(),
      languages: const ['English'],
    );
  }

  Future<void> _toggleLanguage(String language, DoctorModel doc) async {
    if (_isSavingLanguages) return;

    final currentLangs = List<String>.from(doc.languages);
    if (currentLangs.contains(language)) {
      if (currentLangs.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('At least one consultation language is required.'),
            backgroundColor: AppTheme.gsNavy,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      currentLangs.remove(language);
    } else {
      currentLangs.add(language);
    }

    setState(() {
      _isSavingLanguages = true;
    });

    try {
      await _patientService.updateDoctorProfessionalProfile(
        doctorId: doc.id,
        languages: currentLangs,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Consultation languages updated (${currentLangs.join(", ")})'),
            backgroundColor: AppTheme.gsNavy,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update languages: $e'),
            backgroundColor: AppTheme.gsRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLanguages = false;
        });
      }
    }
  }

  String _encodeDoctorPhotoDataUri(Uint8List bytes, String? fileName) {
    final lowerName = (fileName ?? '').toLowerCase();
    final mime = (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg'))
        ? 'image/jpeg'
        : (lowerName.endsWith('.webp') ? 'image/webp' : 'image/png');
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Future<void> _showEditProfileDialog(BuildContext context, DoctorModel doc) async {
    final nameCtrl = TextEditingController(text: doc.name);
    final phoneCtrl = TextEditingController(text: doc.phone);
    final specialtyCtrl = TextEditingController(text: doc.specialty);
    final qualCtrl = TextEditingController(text: doc.qualification);
    final clinicCtrl = TextEditingController(text: doc.clinicName);
    final clinicAddressCtrl = TextEditingController(text: doc.clinicAddress);
    final feeCtrl = TextEditingController(text: doc.consultationFee);
    final cityCtrl = TextEditingController(text: doc.city);
    final stateCtrl = TextEditingController(text: doc.state);
    final pincodeCtrl = TextEditingController(text: doc.pincode);

    final formKey = GlobalKey<FormState>();
    const int maxImageBytes = 5 * 1024 * 1024;
    Uint8List? pickedPhotoBytes = doc.photoBytes;
    String? pickedPhotoName;
    bool hasNewPickedPhoto = false;
    bool removeExistingPhoto = false;
    double? selectedLat = doc.latitude;
    double? selectedLng = doc.longitude;
    bool clearLocationFlag = false;
    bool isSaving = false;
    String? photoError;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final hasExistingUrl = !removeExistingPhoto &&
                doc.profileImageUrl != null &&
                doc.profileImageUrl!.trim().isNotEmpty;
            final hasAnyPhoto = (pickedPhotoBytes != null && pickedPhotoBytes!.isNotEmpty) || hasExistingUrl;

            Future<void> pickPhoto(ImageSource source) async {
              try {
                Uint8List? bytes;
                String? name;
                final override = DoctorProfileScreen.debugPickProfileImageOverride;
                if (override != null) {
                  final picked = await override(source);
                  if (picked == null) return;
                  bytes = picked.bytes;
                  name = picked.name;
                } else {
                  final picker = ImagePicker();
                  final XFile? file = await picker.pickImage(
                    source: source,
                    maxWidth: 900,
                    imageQuality: 80,
                  );
                  if (file == null) return;
                  bytes = await file.readAsBytes();
                  name = file.name;
                }
                if (bytes.isEmpty) {
                  setSheetState(() {
                    photoError = 'Selected image is empty. Please choose another photo.';
                  });
                  return;
                }
                if (bytes.length > maxImageBytes) {
                  setSheetState(() {
                    photoError = 'Image exceeds 5 MB limit. Please choose a smaller photo.';
                  });
                  return;
                }
                setSheetState(() {
                  pickedPhotoBytes = bytes;
                  pickedPhotoName = name;
                  hasNewPickedPhoto = true;
                  removeExistingPhoto = false;
                  photoError = null;
                });
              } catch (e) {
                setSheetState(() {
                  photoError = 'Unable to select photo. Please try again.';
                });
              }
            }

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.88,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Edit Doctor Profile',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Update your professional & clinic details on GS HEALTH',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                      // Profile Image Upload Section (Optional)
                      Container(
                        key: const Key('edit_doctor_photo_section'),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: photoError != null ? AppTheme.gsRed : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PROFILE IMAGE (OPTIONAL)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Container(
                                  key: const Key('edit_doctor_photo_preview'),
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: AppTheme.gsNavy.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: pickedPhotoBytes != null && pickedPhotoBytes!.isNotEmpty
                                      ? Image.memory(
                                          pickedPhotoBytes!,
                                          key: const Key('edit_doctor_photo_preview_memory'),
                                          fit: BoxFit.cover,
                                        )
                                      : hasExistingUrl
                                          ? Image.network(
                                              doc.profileImageUrl!.trim(),
                                              key: const Key('edit_doctor_photo_preview_network'),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => const Icon(
                                                Icons.person_rounded,
                                                size: 34,
                                                color: AppTheme.gsNavy,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.person_rounded,
                                              size: 34,
                                              color: AppTheme.gsNavy,
                                            ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hasAnyPhoto ? 'Profile photo ready' : 'Add a profile photo',
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        pickedPhotoName ??
                                            (hasExistingUrl
                                                ? 'Shown in Find Doctors & Profile'
                                                : 'JPG, PNG, or WEBP (max 5 MB)'),
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF64748B),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          OutlinedButton.icon(
                                            key: const Key('edit_doctor_pick_gallery_button'),
                                            onPressed: isSaving ? null : () => pickPhoto(ImageSource.gallery),
                                            icon: const Icon(Icons.photo_library_outlined, size: 15),
                                            label: Text(
                                              hasAnyPhoto ? 'Change Photo' : 'Gallery',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: AppTheme.gsNavy,
                                              side: const BorderSide(color: AppTheme.gsNavy),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              minimumSize: const Size(0, 32),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                          ),
                                          if (!kIsWeb)
                                            OutlinedButton.icon(
                                              key: const Key('edit_doctor_pick_camera_button'),
                                              onPressed: isSaving ? null : () => pickPhoto(ImageSource.camera),
                                              icon: const Icon(Icons.camera_alt_outlined, size: 15),
                                              label: const Text(
                                                'Camera',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: AppTheme.gsNavy,
                                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                minimumSize: const Size(0, 32),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                            ),
                                          if (hasAnyPhoto)
                                            TextButton.icon(
                                              key: const Key('edit_doctor_remove_photo_button'),
                                              onPressed: isSaving
                                                  ? null
                                                  : () {
                                                      setSheetState(() {
                                                        pickedPhotoBytes = null;
                                                        pickedPhotoName = null;
                                                        hasNewPickedPhoto = false;
                                                        removeExistingPhoto = true;
                                                        photoError = null;
                                                      });
                                                    },
                                              icon: const Icon(Icons.delete_outline_rounded, size: 15, color: AppTheme.gsRed),
                                              label: const Text(
                                                'Remove',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.gsRed,
                                                ),
                                              ),
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                minimumSize: const Size(0, 32),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (photoError != null && photoError!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                photoError!,
                                key: const Key('edit_doctor_photo_error'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.gsRed,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Doctor Name',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter doctor name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Registered Mobile Number',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter phone number' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: specialtyCtrl,
                        decoration: InputDecoration(
                          labelText: 'Specialization (e.g. Endodontist)',
                          prefixIcon: const Icon(Icons.medical_services_outlined),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter specialization' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: qualCtrl,
                        decoration: InputDecoration(
                          labelText: 'Qualifications (e.g. BDS, MDS)',
                          prefixIcon: const Icon(Icons.school_outlined),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter qualification' : null,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        key: const Key('edit_doctor_clinic_name_field'),
                        controller: clinicCtrl,
                        decoration: InputDecoration(
                          labelText: 'Clinic Name',
                          prefixIcon: const Icon(Icons.apartment_rounded),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter clinic name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('edit_doctor_clinic_address_field'),
                        controller: clinicAddressCtrl,
                        minLines: 2,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Clinic Address',
                          hintText: 'Building, street, area, landmark',
                          prefixIcon: const Icon(Icons.place_outlined),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('edit_doctor_state_field'),
                              controller: stateCtrl,
                              decoration: InputDecoration(
                                labelText: 'State',
                                prefixIcon: const Icon(Icons.map_outlined),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              key: const Key('edit_doctor_pincode_field'),
                              controller: pincodeCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Pincode',
                                prefixIcon: const Icon(Icons.pin_drop_outlined),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                if (!ClinicDirectionsHelper.isValidPincode(v)) return '6-digit PIN';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // OpenStreetMap Clinic Location Picker / Preview
                      if (ClinicDirectionsHelper.hasValidCoordinates(selectedLat, selectedLng)) ...[
                        OsmLocationPreviewCard(
                          key: const Key('edit_doctor_osm_preview'),
                          latitude: selectedLat!,
                          longitude: selectedLng!,
                          title: clinicCtrl.text.trim().isNotEmpty
                              ? clinicCtrl.text.trim()
                              : 'Selected Clinic Location',
                          subtitle: clinicAddressCtrl.text.trim(),
                          mapHeight: 120,
                          onChangeLocation: isSaving
                              ? null
                              : () async {
                                  final picked = await MapLocationPickerDialog.show(
                                    context: sheetCtx,
                                    initialAddress: clinicAddressCtrl.text,
                                    initialCity: cityCtrl.text,
                                    initialState: stateCtrl.text,
                                    initialPincode: pincodeCtrl.text,
                                    initialLat: selectedLat,
                                    initialLng: selectedLng,
                                  );
                                  if (picked != null) {
                                    setSheetState(() {
                                      selectedLat = picked.latitude;
                                      selectedLng = picked.longitude;
                                      clearLocationFlag = false;
                                      if (picked.address.isNotEmpty) clinicAddressCtrl.text = picked.address;
                                      if (picked.city.isNotEmpty) cityCtrl.text = picked.city;
                                      if (picked.state.isNotEmpty) stateCtrl.text = picked.state;
                                      if (picked.pincode.isNotEmpty) pincodeCtrl.text = picked.pincode;
                                    });
                                  }
                                },
                          onRemoveLocation: isSaving
                              ? null
                              : () {
                                  setSheetState(() {
                                    selectedLat = null;
                                    selectedLng = null;
                                    clearLocationFlag = true;
                                  });
                                },
                        ),
                        const SizedBox(height: 12),
                      ] else ...[
                        OutlinedButton.icon(
                          key: const Key('edit_doctor_open_map_button'),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final picked = await MapLocationPickerDialog.show(
                                    context: sheetCtx,
                                    initialAddress: clinicAddressCtrl.text,
                                    initialCity: cityCtrl.text,
                                    initialState: stateCtrl.text,
                                    initialPincode: pincodeCtrl.text,
                                    initialLat: selectedLat,
                                    initialLng: selectedLng,
                                  );
                                  if (picked != null) {
                                    setSheetState(() {
                                      selectedLat = picked.latitude;
                                      selectedLng = picked.longitude;
                                      clearLocationFlag = false;
                                      if (picked.address.isNotEmpty) clinicAddressCtrl.text = picked.address;
                                      if (picked.city.isNotEmpty) cityCtrl.text = picked.city;
                                      if (picked.state.isNotEmpty) stateCtrl.text = picked.state;
                                      if (picked.pincode.isNotEmpty) pincodeCtrl.text = picked.pincode;
                                    });
                                  }
                                },
                          icon: const Icon(Icons.add_location_alt_outlined, size: 17),
                          label: const Text(
                            'Select Clinic Location',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.gsNavy,
                            side: const BorderSide(color: AppTheme.gsNavy),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: feeCtrl,
                              decoration: InputDecoration(
                                labelText: 'Consultation Fee',
                                prefixIcon: const Icon(Icons.currency_rupee_rounded),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: cityCtrl,
                              decoration: InputDecoration(
                                labelText: 'City',
                                prefixIcon: const Icon(Icons.location_city_rounded),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          key: const Key('save_doctor_profile_button'),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  setSheetState(() {
                                    isSaving = true;
                                    photoError = null;
                                  });

                                  final String? photoDataUri =
                                      (hasNewPickedPhoto && pickedPhotoBytes != null && pickedPhotoBytes!.isNotEmpty)
                                          ? _encodeDoctorPhotoDataUri(pickedPhotoBytes!, pickedPhotoName)
                                          : null;

                                  final result = await _patientService.updateDoctorProfessionalProfile(
                                    doctorId: doc.id,
                                    name: nameCtrl.text.trim(),
                                    phone: phoneCtrl.text.trim(),
                                    specialty: specialtyCtrl.text.trim(),
                                    qualification: qualCtrl.text.trim(),
                                    clinicName: clinicCtrl.text.trim(),
                                    clinicAddress: clinicAddressCtrl.text.trim(),
                                    state: stateCtrl.text.trim(),
                                    pincode: pincodeCtrl.text.trim(),
                                    latitude: selectedLat,
                                    longitude: selectedLng,
                                    clearLocation: clearLocationFlag,
                                    consultationFee: feeCtrl.text.trim(),
                                    city: cityCtrl.text.trim(),
                                    photoBytes: removeExistingPhoto ? null : pickedPhotoBytes,
                                    profilePhotoDataUri: photoDataUri,
                                    removeProfilePhoto: removeExistingPhoto,
                                  );

                                  if (result['success'] != true) {
                                    final errMsg = (result['message'] ?? 'Failed to upload profile photo. Please try again.').toString();
                                    if (sheetCtx.mounted) {
                                      setSheetState(() {
                                        isSaving = false;
                                        photoError = errMsg;
                                      });
                                    }
                                    return;
                                  }

                                  if (sheetCtx.mounted) {
                                    Navigator.of(sheetCtx).pop();
                                  }

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Doctor profile updated successfully.'),
                                        backgroundColor: AppTheme.gsNavy,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.gsNavy,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDoctorReviewsDialog(BuildContext context, DoctorModel doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (innerCtx, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Patient Reviews',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Verified feedback from consulted patients',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0x14FE3434),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0x40FE3434)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, color: Color(0xFFFE3434), size: 18),
                                const SizedBox(width: 4),
                                Text(
                                  doc.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: Color(0xFFFE3434),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '(${doc.reviewCount})',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFFE3434)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const Key('close_reviews_dialog_button'),
                            onPressed: () => Navigator.of(innerCtx).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: const [
                        Icon(Icons.rate_review_outlined, color: Color(0xFF94A3B8), size: 32),
                        SizedBox(height: 10),
                        Text(
                          'No patient reviews yet.',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Verified feedback submitted by patients after completed visits will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _callHelpline(BuildContext context) async {
    final uri = Uri.parse('tel:$clinicalHelplineNumber');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Clinical care helpline: $clinicalHelplineNumber'),
              backgroundColor: AppTheme.gsNavy,
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clinical care helpline: $clinicalHelplineNumber'),
            backgroundColor: AppTheme.gsNavy,
          ),
        );
      }
    }
  }

  void _showTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Terms of Use',
          key: Key('terms_dialog_title'),
          style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'GS HEALTH Clinical Provider Terms of Use:\n\n'
            '1. Provider Conduct: Licensed doctors agree to maintain clinical confidentiality and uphold national dental medical council ethical codes.\n\n'
            '2. Digital Prescriptions: E-prescriptions issued through GS HEALTH carry legal validity under telemedicine guidelines.\n\n'
            '3. Patient Referrals: Inter-specialty referrals must be conducted with accurate patient notes and prompt specialist triage.\n\n'
            '4. Availability & Appointments: Verified practitioners agree to maintain accurate consultation schedules and respect booked time slots.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xFF334155)),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('close_terms_dialog_button'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: AppTheme.gsNavy, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Privacy Policy',
          key: Key('privacy_dialog_title'),
          style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'GS HEALTH Provider Privacy Policy:\n\n'
            '1. Provider Data: Personal phone numbers, license credentials, and medical degrees are encrypted and verified against medical registries.\n\n'
            '2. Consultation Security: Clinical chats, diagnostic scans, and appointment logs are end-to-end encrypted.\n\n'
            '3. Patient Access Control: Patient contact details are restricted exclusively to authorized and assigned doctors.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xFF334155)),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('close_privacy_dialog_button'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: AppTheme.gsNavy, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Log out?',
          style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        content: const Text(
          'Are you sure you want to log out of your doctor workspace? Unsaved changes will be lost.',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
            key: const Key('cancel_logout_button'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.gsNavy)),
          ),
          ElevatedButton(
            key: const Key('confirm_logout_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gsRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await SessionService().clearSession();
    await _patientService.clearAllDataAndStorage();

    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logged out of Doctor workspace.'),
        backgroundColor: AppTheme.gsNavy,
        duration: Duration(seconds: 2),
      ),
    );
    try {
      context.go('/login');
    } catch (_) {}
  }

  Future<void> _confirmAndDeleteDoctorAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete my account?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        content: const Text(
          'Are you sure you want to permanently delete your GS HEALTH Doctor account, clinical profile, and practice listings? This action cannot be undone.',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
            key: const Key('cancel_delete_account_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.gsNavy,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('confirm_delete_account_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gsRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'Delete account',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _patientService.deleteCurrentDoctorAccount();
    await SessionService().clearSession();

    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your Doctor account has been permanently deleted.'),
        backgroundColor: AppTheme.gsNavy,
      ),
    );
    try {
      context.go('/login');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final doc = _resolveCurrentDoctor();
    final selectedLangs = doc.languages.isNotEmpty ? doc.languages : const ['English'];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Circular Back Button & Title
              Row(
                children: [
                  InkWell(
                    key: const Key('doctor_profile_back_button'),
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        context.go('/dentist');
                      }
                    },
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.chevron_left_rounded,
                          color: Color(0xFF0F172A),
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 1. Profile Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Avatar Squircle (Red / Doctor photo — tap to edit)
                    GestureDetector(
                      key: const Key('doctor_own_profile_avatar_tap'),
                      onTap: () => _showEditProfileDialog(context, doc),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppTheme.gsRed,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: doc.photoBytes != null && doc.photoBytes!.isNotEmpty
                                  ? Image.memory(
                                      doc.photoBytes!,
                                      key: const Key('doctor_own_profile_avatar_memory'),
                                      fit: BoxFit.cover,
                                    )
                                  : (doc.profileImageUrl != null && doc.profileImageUrl!.trim().isNotEmpty)
                                      ? Image.network(
                                          doc.profileImageUrl!.trim(),
                                          key: const Key('doctor_own_profile_avatar_network'),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Center(
                                            child: Icon(
                                              Icons.person_rounded,
                                              color: Colors.white,
                                              size: 42,
                                            ),
                                          ),
                                        )
                                      : const Center(
                                          child: Icon(
                                            Icons.person_rounded,
                                            color: Colors.white,
                                            size: 42,
                                          ),
                                        ),
                            ),
                          ),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: AppTheme.gsNavy,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Doctor Name
                    Text(
                      doc.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Role Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Text(
                        'Doctor',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Registered Mobile Number with phone icon
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.phone_outlined,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            doc.phone.isNotEmpty ? doc.phone : 'Not provided',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Edit Profile Button
                    OutlinedButton.icon(
                      key: const Key('doctor_profile_edit_button'),
                      onPressed: () => _showEditProfileDialog(context, doc),
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Color(0xFF0F172A),
                      ),
                      label: const Text(
                        'Edit profile',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFF8FAFC),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Languages You Consult In Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'LANGUAGES YOU CONSULT IN',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        Container(
                          key: const Key('doctor_profile_saved_languages_badge'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x14012A58),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Saved: ${selectedLangs.join(", ")}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.gsNavy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: availableLanguages.map((lang) {
                        final isSelected = selectedLangs.contains(lang);
                        return InkWell(
                          key: Key('doctor_language_chip_$lang'),
                          onTap: () => _toggleLanguage(lang, doc),
                          borderRadius: BorderRadius.circular(22),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.gsNavy : Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isSelected ? AppTheme.gsNavy : const Color(0xFFE2E8F0),
                                width: 1.2,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.gsNavy.withValues(alpha: 0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              lang,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                color: isSelected ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. Practice Details Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'PRACTICE',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          key: const Key('doctor_profile_edit_clinic_button'),
                          onPressed: () => _showEditProfileDialog(context, doc),
                          icon: const Icon(Icons.edit_location_alt_outlined, size: 15),
                          label: const Text(
                            'Edit clinic details',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.gsNavy,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Specialization
                    Text(
                      doc.specialty.isNotEmpty ? doc.specialty : 'General Dentistry',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Qualifications
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.school_outlined,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            doc.qualification.isNotEmpty ? doc.qualification : 'BDS, MDS',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Clinic Name
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.apartment_rounded,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            doc.clinicName.trim().isNotEmpty
                                ? doc.clinicName.trim()
                                : 'Clinic name not set',
                            key: const Key('doctor_profile_clinic_name_text'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (doc.clinicAddress.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.place_outlined,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              doc.clinicAddress.trim(),
                              key: const Key('doctor_profile_clinic_address_text'),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (doc.city.trim().isNotEmpty ||
                        doc.state.trim().isNotEmpty ||
                        doc.pincode.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.location_city_rounded,
                            size: 18,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              [
                                if (doc.city.trim().isNotEmpty) doc.city.trim(),
                                if (doc.state.trim().isNotEmpty) doc.state.trim(),
                                if (doc.pincode.trim().isNotEmpty) doc.pincode.trim(),
                              ].join(', '),
                              key: const Key('doctor_profile_city_state_pincode_text'),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (doc.hasCoordinates)
                      OsmLocationPreviewCard(
                        key: const Key('doctor_profile_osm_preview'),
                        latitude: doc.latitude!,
                        longitude: doc.longitude!,
                        title: doc.clinicName.trim().isNotEmpty ? doc.clinicName.trim() : 'Selected Clinic Location',
                        subtitle: doc.clinicAddress.trim(),
                        mapHeight: 118,
                        onChangeLocation: () => _showEditProfileDialog(context, doc),
                      )
                    else
                      Container(
                        key: const Key('doctor_profile_no_map_pin_banner'),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_off_outlined, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Clinic map location not set yet',
                                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: () => _showEditProfileDialog(context, doc),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.gsNavy,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                minimumSize: const Size(0, 28),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Select Clinic Location',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),

                    // Languages Known Summary Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.translate_rounded,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Languages Known: ${selectedLangs.join(", ")}',
                            key: const Key('doctor_profile_languages_summary'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Verification Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0x14012A58),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x40012A58)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            doc.verified ? Icons.check_circle_rounded : Icons.shield_outlined,
                            size: 15,
                            color: const Color(0xFFFE3434),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            doc.verified ? 'VERIFIED ON GS HEALTH' : 'PENDING VERIFICATION ON GS HEALTH',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF012A58),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 4. Profile Menu Card
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildMenuItem(
                      key: const Key('doctor_profile_referrals_button'),
                      icon: Icons.hub_outlined,
                      title: 'Referrals',
                      onTap: () => ReferredPatientsSheet.show(context),
                    ),
                    const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                    _buildMenuItem(
                      key: const Key('doctor_profile_refer_specialist_button'),
                      icon: Icons.person_add_outlined,
                      title: 'Refer to a specialist or clinic',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DentistTimelineScreen(initialTabIndex: 3),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                    _buildMenuItem(
                      key: const Key('doctor_profile_reviews_button'),
                      icon: Icons.star_outline_rounded,
                      title: 'Patient reviews',
                      onTap: () => _showDoctorReviewsDialog(context, doc),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 5. NEED HELP? Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: InkWell(
                  onTap: () => _callHelpline(context),
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'NEED HELP?',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.call_outlined,
                            size: 16,
                            color: AppTheme.gsNavy.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Call our 24/7 clinical care helpline for medical emergencies, appointments and consultations.',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF334155),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 6. Account Actions Stack
              Column(
                children: [
                  // Log Out Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      key: const Key('doctor_profile_logout_button'),
                      onPressed: () => _confirmLogout(context),
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: AppTheme.gsRed,
                        size: 18,
                      ),
                      label: const Text(
                        'Log out',
                        style: TextStyle(
                          color: AppTheme.gsRed,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppTheme.gsRed.withValues(alpha: 0.08),
                        side: BorderSide(color: AppTheme.gsRed.withValues(alpha: 0.2)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Terms of Use
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      key: const Key('doctor_profile_terms_button'),
                      onPressed: () => _showTermsDialog(context),
                      icon: const Icon(
                        Icons.description_outlined,
                        color: Color(0xFF0F172A),
                        size: 18,
                      ),
                      label: const Text(
                        'Terms of Use',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Privacy Policy
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      key: const Key('doctor_profile_privacy_button'),
                      onPressed: () => _showPrivacyDialog(context),
                      icon: const Icon(
                        Icons.shield_outlined,
                        color: Color(0xFF0F172A),
                        size: 18,
                      ),
                      label: const Text(
                        'Privacy Policy',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Delete My Account
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      key: const Key('doctor_profile_delete_account_button'),
                      onPressed: () => _confirmAndDeleteDoctorAccount(context),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFF0F172A),
                        size: 18,
                      ),
                      label: const Text(
                        'Delete my account',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required Key key,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: const Color(0xFF0F172A),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}
