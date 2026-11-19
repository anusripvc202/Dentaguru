import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/utils/record_file_helper.dart';
import '../widgets/referred_patients_sheet.dart';

/// Refer a Friend Screen designed to match the GS HEALTH reference UI.
class ReferAFriendScreen extends StatefulWidget {
  final DoctorModel? preselectedDoctor;

  const ReferAFriendScreen({
    super.key,
    this.preselectedDoctor,
  });

  @override
  State<ReferAFriendScreen> createState() => _ReferAFriendScreenState();
}

class _ReferAFriendScreenState extends State<ReferAFriendScreen> {
  final PatientProblemService _patientService = PatientProblemService();
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _searchController = TextEditingController();
  final _noteController = TextEditingController();

  // Focus Nodes
  final _nameFocus = FocusNode();
  final _mobileFocus = FocusNode();
  final _searchFocus = FocusNode();
  final _noteFocus = FocusNode();

  // Doctor Selection State
  DoctorModel? _selectedDoctor;
  String _searchQuery = '';

  // Attachments State (max 5)
  final List<PickedRecordFile> _attachments = [];
  final ImagePicker _picker = ImagePicker();

  // Submission State
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _patientService.syncDoctorsFromApi();
    _patientService.syncMyDoctorsFromApi();

    if (widget.preselectedDoctor != null && widget.preselectedDoctor!.isAvailable) {
      _selectedDoctor = widget.preselectedDoctor;
    } else if (_patientService.myDoctors.any((d) => d.isAvailable)) {
      _selectedDoctor = _patientService.myDoctors.firstWhere((d) => d.isAvailable);
    } else if (_patientService.availableDoctors.isNotEmpty) {
      _selectedDoctor = _patientService.availableDoctors.first;
    }

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _searchController.dispose();
    _noteController.dispose();
    _nameFocus.dispose();
    _mobileFocus.dispose();
    _searchFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  List<DoctorModel> _getFilteredDoctors() {
    final allDocs = _patientService.availableDoctors;
    final favDocs = _patientService.myDoctors.where((d) => d.isAvailable).toList();

    // Prioritize favourite doctors first, then rest
    final orderedDocs = <DoctorModel>[];
    if (widget.preselectedDoctor != null && widget.preselectedDoctor!.isAvailable) {
      orderedDocs.add(widget.preselectedDoctor!);
    }
    for (final doc in favDocs) {
      if (!orderedDocs.any((d) => d.id == doc.id || (d.name == doc.name && d.clinicName == doc.clinicName))) {
        orderedDocs.add(doc);
      }
    }
    for (final doc in allDocs) {
      if (!orderedDocs.any((d) => d.id == doc.id || (d.name == doc.name && d.clinicName == doc.clinicName))) {
        orderedDocs.add(doc);
      }
    }

    if (_searchQuery.isEmpty) {
      return orderedDocs;
    }

    return orderedDocs.where((doc) {
      final name = doc.name.toLowerCase();
      final specialty = doc.specialty.toLowerCase();
      final clinic = doc.clinicName.toLowerCase();
      final city = doc.city.toLowerCase();
      return name.contains(_searchQuery) ||
          specialty.contains(_searchQuery) ||
          clinic.contains(_searchQuery) ||
          city.contains(_searchQuery);
    }).toList();
  }

  bool _isDoctorFavourite(DoctorModel doc) {
    return _patientService.myDoctors.any(
      (d) => d.id == doc.id || (d.name.isNotEmpty && d.name.toLowerCase() == doc.name.toLowerCase()),
    );
  }

  // ─────────────────────────────────────────────
  // ATTACHMENT PICKERS (Gallery, Camera, PDF)
  // ─────────────────────────────────────────────
  Future<void> _pickFromGallery() async {
    if (_attachments.length >= 5) {
      _showLimitReachedMessage();
      return;
    }
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (image != null) {
        await _processAndAddFile(image);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to select image from gallery: $e');
    }
  }

  Future<void> _pickFromCamera() async {
    if (_attachments.length >= 5) {
      _showLimitReachedMessage();
      return;
    }
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (photo != null) {
        await _processAndAddFile(photo);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to capture photo with camera: $e');
    }
  }

  Future<void> _pickPdf() async {
    if (_attachments.length >= 5) {
      _showLimitReachedMessage();
      return;
    }
    try {
      final file = await RecordFileHelper.pickRecordFile();
      if (file != null) {
        final validationError = RecordFileHelper.validatePickedFile(file);
        if (validationError != null) {
          _showErrorSnackBar(validationError);
          return;
        }
        setState(() {
          _attachments.add(file);
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to select PDF document: $e');
    }
  }

  Future<void> _processAndAddFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final name = file.name;
    final size = bytes.length;
    final ext = RecordFileHelper.extractExtension(name, mimeType: file.mimeType);

    if (size > RecordFileHelper.maxFileSizeBytes) {
      _showErrorSnackBar('File size exceeds the 20 MB limit.');
      return;
    }

    final picked = PickedRecordFile(
      name: name,
      extension: ext.isNotEmpty ? ext : 'JPG',
      mimeType: file.mimeType ?? 'image/jpeg',
      sizeBytes: size,
      bytes: bytes,
    );

    setState(() {
      _attachments.add(picked);
    });
  }

  void _removeAttachment(int index) {
    if (index >= 0 && index < _attachments.length) {
      setState(() {
        _attachments.removeAt(index);
      });
    }
  }

  void _showLimitReachedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Maximum 5 attachments allowed per referral.'),
        backgroundColor: AppTheme.gsNavy,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.gsRed,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SUBMIT REFERRAL
  // ─────────────────────────────────────────────
  Future<void> _handleSendReferral() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_isSubmitting) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDoctor == null) {
      setState(() {
        _errorMessage = 'Please select a doctor to refer your friend to.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final friendName = _nameController.text.trim();
    final friendMobile = _mobileController.text.trim();
    final note = _noteController.text.trim();
    final selectedDoc = _selectedDoctor!;

    try {
      // 1. Submit referral to backend API and Supabase
      final res = await _patientService.submitPatientReferral(
        referredPatientName: friendName,
        referredPatientMobile: friendMobile,
        referredPatientAge: '28',
        referredPatientGender: 'Female',
        referredPatientCity: selectedDoc.city.isNotEmpty ? selectedDoc.city : 'Hyderabad',
        referredPatientPincode: selectedDoc.pincode.isNotEmpty ? selectedDoc.pincode : '500001',
        referredPatientLocation: selectedDoc.clinicAddress.isNotEmpty ? selectedDoc.clinicAddress : selectedDoc.clinicName,
        requiredSpecialist: selectedDoc.specialty.isNotEmpty ? selectedDoc.specialty : 'General Dentistry',
        clinicalComplaint: note.isNotEmpty ? note : 'Referral consultation with ${selectedDoc.name}',
        doctorId: selectedDoc.id.isNotEmpty ? selectedDoc.id : selectedDoc.userId,
        doctorName: selectedDoc.name,
        doctorClinicName: selectedDoc.clinicName,
        doctorCity: selectedDoc.city,
        doctorPincode: selectedDoc.pincode,
        doctorPhone: selectedDoc.phone,
      );

      // 2. If attachments are present, upload them as referral records
      if (_attachments.isNotEmpty && res['success'] == true) {
        final patientId = _patientService.currentPatient.id;
        for (final att in _attachments) {
          try {
            await ApiService().uploadPatientDentalRecord(
              patientId: patientId.isNotEmpty ? patientId : 'patient_${DateTime.now().millisecondsSinceEpoch}',
              patientName: friendName,
              title: 'Referral Document: ${att.name}',
              category: att.isPdf ? 'Medical Report' : 'Medical X-ray',
              description: 'Attachment for referral to ${selectedDoc.name}. Note: $note',
              fileName: att.name,
              fileType: att.extension,
              fileSize: att.sizeBytes,
              fileBytes: att.bytes,
              mimeType: att.mimeType,
            );
          } catch (e) {
            debugPrint('Referral attachment upload notice: $e');
          }
        }
      }

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (res['success'] == true) {
        _showSuccessDialog(friendName, selectedDoc.name);
      } else {
        final message = res['message']?.toString() ?? 'Failed to send referral. Please try again.';
        setState(() {
          _errorMessage = message;
        });
        _showErrorSnackBar(message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Error submitting referral: $e';
      });
      _showErrorSnackBar('Error submitting referral: $e');
    }
  }

  void _showSuccessDialog(String friendName, String doctorName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.gsNavy,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Referral Sent!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'You have referred $friendName to $doctorName. We will keep track of the referral for you.',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.textMedium,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop(); // Close dialog
                        Navigator.of(context).pop(); // Back to dashboard
                        ReferredPatientsSheet.show(context);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.gsNavy,
                        side: const BorderSide(color: AppTheme.gsNavy, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('My referrals', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gsNavy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    final filteredDoctors = _getFilteredDoctors();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar / Header
            _buildHeader(context),

            // Scrollable Referral Form
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Subtitle Description
                      const Text(
                        'Share a doctor you trust. We\'ll keep track of the referral for you.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                          height: 1.4,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 22),

                      // 1. Friend's Name
                      _buildSectionLabel('FRIEND\'S NAME'),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const ValueKey('referral_friend_name_input'),
                        controller: _nameController,
                        focusNode: _nameFocus,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: _inputDecoration(hintText: 'e.g. Amit Verma'),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter your friend\'s full name.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // 2. Friend's Mobile Number
                      _buildSectionLabel('FRIEND\'S MOBILE (+91)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const ValueKey('referral_friend_mobile_input'),
                        controller: _mobileController,
                        focusNode: _mobileFocus,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0F172A),
                          letterSpacing: 0.5,
                        ),
                        decoration: _inputDecoration(hintText: '98765 43210'),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter your friend\'s 10-digit mobile number.';
                          }
                          final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
                          if (digits.length != 10) {
                            return 'Please enter a valid 10-digit Indian mobile number.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // 3. Refer To – Dentist Selection
                      _buildSectionLabel('REFER TO'),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const ValueKey('referral_doctor_search_input'),
                        controller: _searchController,
                        focusNode: _searchFocus,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: _inputDecoration(
                          hintText: 'Search doctor by name, specialty...',
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 18),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Showing your favourite and visited doctors. Search to find others.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Doctor Selection Cards
                      if (filteredDoctors.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Center(
                            child: Text(
                              'No doctors found matching your search.',
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredDoctors.length > 5 && _searchQuery.isEmpty ? 4 : filteredDoctors.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final doc = filteredDoctors[index];
                            final isSelected = _selectedDoctor?.id == doc.id ||
                                (_selectedDoctor != null &&
                                    _selectedDoctor!.name == doc.name &&
                                    _selectedDoctor!.clinicName == doc.clinicName);
                            final isFav = _isDoctorFavourite(doc);

                            return _buildDoctorCard(doc, isSelected, isFav);
                          },
                        ),
                      const SizedBox(height: 20),

                      // 4. Note (Optional)
                      _buildSectionLabel('NOTE (OPTIONAL)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const ValueKey('referral_note_input'),
                        controller: _noteController,
                        focusNode: _noteFocus,
                        minLines: 3,
                        maxLines: 4,
                        maxLength: 250,
                        style: const TextStyle(
                          fontSize: 14.5,
                          color: Color(0xFF0F172A),
                          height: 1.35,
                        ),
                        decoration: _inputDecoration(
                          hintText: 'e.g. Looking for braces consultation',
                        ).copyWith(
                          counterStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 5. Attach Photos, X-rays or Reports (Optional)
                      _buildSectionLabel('ATTACH PHOTOS, X-RAYS OR REPORTS (OPTIONAL) (${_attachments.length}/5)'),
                      const SizedBox(height: 10),

                      // 3 Action Pill Buttons (Gallery, Camera, PDF)
                      Row(
                        children: [
                          Expanded(
                            child: _buildAttachmentPillButton(
                              label: 'Gallery',
                              icon: Icons.image_outlined,
                              onTap: _pickFromGallery,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAttachmentPillButton(
                              label: 'Camera',
                              icon: Icons.camera_alt_outlined,
                              onTap: _pickFromCamera,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAttachmentPillButton(
                              label: 'PDF',
                              icon: Icons.picture_as_pdf_outlined,
                              onTap: _pickPdf,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Attachments Preview Chips
                      if (_attachments.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _attachments.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final file = entry.value;
                            return _buildAttachmentPreviewChip(file, idx);
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Error Banner if present
                      if (_errorMessage != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0x14FE3434),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0x40FE3434)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppTheme.gsRed, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Color(0xFFFE3434), fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      const SizedBox(height: 80), // Bottom breathing room for sticky/bottom button
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Sticky "Send referral" Button
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // UI SUB-COMPONENTS
  // ─────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Refer a friend',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Color(0xFF64748B),
        letterSpacing: 0.5,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        fontSize: 14.5,
        color: Color(0xFF94A3B8),
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.gsNavy, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.gsRed, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.gsRed, width: 1.6),
      ),
    );
  }

  Widget _buildDoctorCard(DoctorModel doc, bool isSelected, bool isFav) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedDoctor = doc;
          _errorMessage = null;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.gsNavy.withValues(alpha: 0.03) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.gsNavy : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Red Rounded Doctor Avatar (Matching Screenshot)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.gsRed,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: doc.photoBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          doc.photoBytes!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Text(
                        doc.name.isNotEmpty
                            ? (doc.name.startsWith('Dr.') && doc.name.length > 3
                                ? doc.name.substring(3).trim()[0].toUpperCase()
                                : doc.name[0].toUpperCase())
                            : 'D',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // Doctor Info (Name, Specialty, Clinic)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (isFav) ...[
                        const Icon(
                          Icons.favorite_rounded,
                          color: AppTheme.gsRed,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          '${doc.specialty} · ${doc.clinicName.isNotEmpty ? doc.clinicName : 'Clinic'}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Radio Control
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.gsNavy : const Color(0xFFCBD5E1),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.gsNavy,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPillButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF475569)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreviewChip(PickedRecordFile file, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            file.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
            size: 16,
            color: file.isPdf ? AppTheme.gsRed : AppTheme.gsNavy,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              file.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '(${file.formattedSize})',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _removeAttachment(index),
            child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFF1F5F9), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          key: const ValueKey('referral_send_button'),
          onPressed: _isSubmitting ? null : _handleSendReferral,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                )
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(
            _isSubmitting ? 'Sending referral...' : 'Send referral',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.gsNavy,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}
