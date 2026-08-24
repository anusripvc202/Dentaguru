import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';

class PatientDetailsScreen extends StatefulWidget {
  final PatientProfile patient;
  final Function(BuildContext, PatientConsultationRequest, {DoctorModel? preSelectedDoctor})? onAssignDoctor;

  const PatientDetailsScreen({
    super.key,
    required this.patient,
    this.onAssignDoctor,
  });

  @override
  State<PatientDetailsScreen> createState() => _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  final PatientProblemService _problemService = PatientProblemService();
  bool _isRefreshing = false;
  int _selectedDoctorFilterIndex = 0; // 0: All Dentists, 1: Location / Pincode Matches, 2: Language Matches

  // Expand / Collapse View Details Toggles
  bool _isPatientDetailsExpanded = false;
  bool _isAssignedDentistDetailsExpanded = false;
  final Set<String> _expandedDoctorIds = {};

  // Search Controller for Dentists (Phone, City/Location, Pincode, Name)
  final TextEditingController _doctorSearchController = TextEditingController();
  String _doctorSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  @override
  void dispose() {
    _doctorSearchController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    await _problemService.syncAllDataFromApi();
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    final year = dt.year;
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day $month $year, $hour:$minute $period';
  }

  void _handleAssignDirectly(DoctorModel doctor, PatientConsultationRequest? existingReq) async {
    final reqToAssign = existingReq ??
        PatientConsultationRequest(
          id: 'REQ-PAT-${widget.patient.id.isNotEmpty ? widget.patient.id : DateTime.now().millisecondsSinceEpoch}',
          patientId: widget.patient.id.isNotEmpty ? widget.patient.id : null,
          patientName: widget.patient.name.isNotEmpty ? widget.patient.name : 'Patient',
          patientPhone: widget.patient.phone.isNotEmpty ? widget.patient.phone : 'Not provided',
          problemCategory: 'General Consultation',
          problemDescription: 'Specialist dental consultation assigned by Administrator.',
          severity: 'Moderate',
          city: widget.patient.city,
          state: widget.patient.state,
          pincode: widget.patient.pincode,
          submittedAt: DateTime.now(),
        );

    final notesController = TextEditingController(text: 'Assigned for specialist dental consultation.');

    final shouldAssign = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: AppTheme.primaryBlue, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Assign ${doctor.name}?',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assigning ${doctor.name} (${doctor.specialty}) to patient ${widget.patient.name.isNotEmpty ? widget.patient.name : "Patient"}.',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🏥 ${doctor.clinicName.isNotEmpty ? doctor.clinicName : "DentaGuru Care Clinic"}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text('📍 ${doctor.city.isNotEmpty ? doctor.city : "Hyderabad"} • PIN: ${doctor.pincode.isNotEmpty ? doctor.pincode : "500001"}', style: const TextStyle(fontSize: 11.5)),
                      const SizedBox(height: 2),
                      Text('🗣️ Languages: ${doctor.languages.isNotEmpty ? doctor.languages.join(", ") : "English, Telugu, Hindi"}', style: const TextStyle(fontSize: 11.5)),
                      if (doctor.phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('📞 Mobile: ${doctor.phone}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Admin Clinical Guidance Notes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Optional instructions for doctor...',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Confirm Assignment', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (shouldAssign == true) {
      await _problemService.assignDoctorToRequest(
        requestId: reqToAssign.id,
        doctor: doctor,
        adminNotes: notesController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 ${doctor.name} successfully assigned to ${widget.patient.name}!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _problemService,
      builder: (context, _) {
        final latestReq = _problemService.getLatestRequestForPatient(widget.patient);
        final assignedDoctor = _problemService.getAssignedDoctorForPatient(widget.patient);
        final bool isAssigned = assignedDoctor != null;

        final String displayName = widget.patient.name.isNotEmpty
            ? widget.patient.name
            : (widget.patient.email.isNotEmpty ? widget.patient.email.split('@').first : 'Patient');

        final allDocs = _problemService.allDoctors;

        // Categorize matching doctors
        final patientCity = widget.patient.city.trim().toLowerCase();
        final patientPin = widget.patient.pincode.trim();
        final patientLangs = widget.patient.languages.map((l) => l.trim().toLowerCase()).toList();

        final locationOrPinMatches = allDocs.where((d) {
          final docCity = d.city.trim().toLowerCase();
          final docPin = d.pincode.trim();
          final bool cityMatch = patientCity.isNotEmpty && docCity.isNotEmpty && (docCity.contains(patientCity) || patientCity.contains(docCity));
          final bool pinMatch = patientPin.isNotEmpty && docPin.isNotEmpty && docPin == patientPin;
          return cityMatch || pinMatch;
        }).toList();

        final languageMatches = allDocs.where((d) {
          return d.languages.any((l) => patientLangs.contains(l.trim().toLowerCase()));
        }).toList();

        // Apply Tab Filter
        List<DoctorModel> baseFilteredDoctors;
        if (_selectedDoctorFilterIndex == 1) {
          baseFilteredDoctors = locationOrPinMatches;
        } else if (_selectedDoctorFilterIndex == 2) {
          baseFilteredDoctors = languageMatches;
        } else {
          baseFilteredDoctors = allDocs;
        }

        // Apply Text Search Filter (phone, city/location, pincode, name, specialty, languages)
        List<DoctorModel> displayedDoctors;
        final cleanQuery = _doctorSearchQuery.trim().toLowerCase();
        if (cleanQuery.isEmpty) {
          displayedDoctors = baseFilteredDoctors;
        } else {
          displayedDoctors = allDocs.where((d) {
            final nameMatch = d.name.toLowerCase().contains(cleanQuery);
            final phoneMatch = d.phone.replaceAll(RegExp(r'[^0-9]'), '').contains(cleanQuery.replaceAll(RegExp(r'[^0-9]'), ''));
            final cityMatch = d.city.toLowerCase().contains(cleanQuery);
            final pinMatch = d.pincode.toLowerCase().contains(cleanQuery);
            final clinicMatch = d.clinicName.toLowerCase().contains(cleanQuery) || d.clinicAddress.toLowerCase().contains(cleanQuery);
            final specialtyMatch = d.specialty.toLowerCase().contains(cleanQuery);
            final languageMatch = d.languages.any((l) => l.toLowerCase().contains(cleanQuery));
            return nameMatch || phoneMatch || cityMatch || pinMatch || clinicMatch || specialtyMatch || languageMatch;
          }).toList();
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textDark, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Patient & Dentist Directory',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            actions: [
              IconButton(
                icon: _isRefreshing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue))
                    : const Icon(Icons.refresh_rounded, color: AppTheme.primaryBlue),
                tooltip: 'Refresh Patient & Dentists',
                onPressed: _isRefreshing ? null : _refreshData,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. TOP PATIENT HEADER BANNER
                _buildPatientHeaderCard(displayName, isAssigned),

                const SizedBox(height: 14),

                // 2. CURRENTLY ASSIGNED DENTIST CARD (WITH VIEW DETAILS TOGGLE)
                _buildAssignedDentistCard(isAssigned, assignedDoctor, latestReq),

                const SizedBox(height: 14),

                // 3. AVAILABLE & SEARCHABLE DENTISTS (BY PHONE, LOCATION, PINCODE & LANGUAGE)
                _buildSearchableDentistsSection(allDocs, locationOrPinMatches, languageMatches, displayedDoctors, assignedDoctor, latestReq),

                const SizedBox(height: 14),

                // 4. COMPLETE PATIENT PROFILE CARD (WITH VIEW DETAILS TOGGLE)
                _buildPatientProfileDetailsCard(),

                const SizedBox(height: 14),

                // 5. PROBLEM & DENTAL COMPLAINT CARD (OVERFLOW SAFE)
                _buildProblemComplaintCard(latestReq),

                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // CARD 1: PATIENT HEADER OVERVIEW
  // ==========================================
  Widget _buildPatientHeaderCard(String displayName, bool isAssigned) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFFEFF6FF),
            backgroundImage: widget.patient.photoBytes != null ? MemoryImage(widget.patient.photoBytes!) : null,
            child: widget.patient.photoBytes == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'P',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(color: Color(0xFF16A34A), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                if (widget.patient.phone.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.phone_android_rounded, size: 13, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        widget.patient.phone,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                    ],
                  ),
                if (widget.patient.email.isNotEmpty && widget.patient.email != '--')
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.alternate_email_rounded, size: 12, color: AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.patient.email,
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: isAssigned ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isAssigned ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isAssigned ? Icons.check_circle_rounded : Icons.pending_rounded,
                            size: 12,
                            color: isAssigned ? const Color(0xFF15803D) : const Color(0xFFB45309),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isAssigned ? 'Assigned' : 'Not Assigned',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isAssigned ? const Color(0xFF15803D) : const Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.patient.city.isNotEmpty && widget.patient.city != '--')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_outlined, size: 11, color: AppTheme.primaryBlue),
                            const SizedBox(width: 3),
                            Text(
                              '${widget.patient.city}${widget.patient.pincode.isNotEmpty && widget.patient.pincode != "--" ? " • PIN: ${widget.patient.pincode}" : ""}',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                            ),
                          ],
                        ),
                      ),
                    if (widget.patient.languages.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.translate_rounded, size: 11, color: Color(0xFF7E22CE)),
                            const SizedBox(width: 3),
                            Text(
                              widget.patient.languages.join(', '),
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF7E22CE)),
                            ),
                          ],
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

  // ==========================================
  // CARD 2: CURRENTLY ASSIGNED DENTIST DETAILS
  // ==========================================
  Widget _buildAssignedDentistCard(bool isAssigned, DoctorModel? doc, PatientConsultationRequest? req) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isAssigned ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.medical_services_rounded,
                size: 17,
                color: isAssigned ? AppTheme.primaryBlue : AppTheme.textMuted,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Currently Assigned Dentist',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isAssigned ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isAssigned ? 'Assigned' : 'Not Assigned',
                  style: TextStyle(
                    color: isAssigned ? const Color(0xFF15803D) : const Color(0xFF64748B),
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (isAssigned && doc != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  backgroundImage: doc.photoBytes != null ? MemoryImage(doc.photoBytes!) : null,
                  child: doc.photoBytes == null
                      ? Text(
                          doc.name.isNotEmpty ? doc.name.replaceAll('Dr. ', '').trim()[0].toUpperCase() : 'D',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        doc.specialty,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '🏥 ${doc.clinicName.isNotEmpty ? doc.clinicName : "DentaGuru Care Clinic"}',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '📍 ${doc.city.isNotEmpty ? doc.city : "Hyderabad"} • PIN: ${doc.pincode.isNotEmpty ? doc.pincode : "500001"}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Toggle View / Hide Complete Details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => setState(() => _isAssignedDentistDetailsExpanded = !_isAssignedDentistDetailsExpanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isAssignedDentistDetailsExpanded ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 13,
                          color: AppTheme.primaryBlue,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isAssignedDentistDetailsExpanded ? 'Hide Details' : 'View Details',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          _isAssignedDentistDetailsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: AppTheme.primaryBlue,
                        ),
                      ],
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.swap_horiz_rounded, size: 14, color: AppTheme.primaryBlue),
                  label: const Text('Reassign', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                  onPressed: () => _handleAssignDirectly(doc, req),
                ),
              ],
            ),

            if (_isAssignedDentistDetailsExpanded) ...[
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 10),

              _buildDetailRow(Icons.school_outlined, 'Qualification', doc.qualification),
              _buildDetailRow(Icons.timeline_rounded, 'Experience', '${doc.experienceYears} Years Experience'),
              _buildDetailRow(Icons.local_hospital_rounded, 'Clinic Name', doc.clinicName),
              if (doc.clinicAddress.isNotEmpty)
                _buildDetailRow(Icons.location_on_rounded, 'Clinic Address', doc.clinicAddress),
              _buildDetailRow(Icons.location_city_rounded, 'City / Location', '${doc.city.isNotEmpty ? doc.city : "Hyderabad"} ${doc.pincode.isNotEmpty ? "• PIN: ${doc.pincode}" : ""}'),
              if (doc.phone.isNotEmpty)
                _buildDetailRow(Icons.phone_rounded, 'Mobile Number', doc.phone),
              if (doc.email.isNotEmpty)
                _buildDetailRow(Icons.email_outlined, 'Email Address', doc.email),
              _buildDetailRow(
                Icons.translate_rounded,
                'Languages Known',
                doc.languages.isNotEmpty ? doc.languages.join(', ') : 'English, Telugu, Hindi',
              ),
              _buildDetailRow(Icons.event_available_rounded, 'Availability Status', doc.status),
              _buildDetailRow(Icons.verified_user_rounded, 'Dentist Status', doc.verificationStatus),
              if (req?.submittedAt != null)
                _buildDetailRow(
                  Icons.calendar_today_rounded,
                  'Assignment Date',
                  _formatDateTime(req!.submittedAt),
                ),
              if (req?.adminNotes != null && req!.adminNotes!.trim().isNotEmpty)
                _buildDetailRow(Icons.notes_rounded, 'Admin Guidance', req.adminNotes!.trim()),
            ],
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: const [
                  Icon(Icons.person_off_outlined, size: 30, color: Color(0xFF94A3B8)),
                  SizedBox(height: 6),
                  Text(
                    'No Dentist Currently Assigned',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Search or select a matching dentist from the list below to assign.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // CARD 3: SEARCHABLE AVAILABLE DENTISTS (PHONE, CITY/LOCATION, PINCODE)
  // =========================================================================
  Widget _buildSearchableDentistsSection(
    List<DoctorModel> allDocs,
    List<DoctorModel> locationMatches,
    List<DoctorModel> languageMatches,
    List<DoctorModel> displayedDoctors,
    DoctorModel? assignedDoctor,
    PatientConsultationRequest? req,
  ) {
    final patientCity = widget.patient.city.trim().toLowerCase();
    final patientPin = widget.patient.pincode.trim();
    final patientLangs = widget.patient.languages.map((l) => l.trim().toLowerCase()).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt_rounded, size: 18, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Search & Available Dentists Directory',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${displayedDoctors.length} found',
                  style: const TextStyle(color: AppTheme.primaryBlue, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 🔍 INTERACTIVE LIVE SEARCH BAR (PHONE, CITY, PINCODE, NAME)
          TextField(
            controller: _doctorSearchController,
            onChanged: (val) => setState(() => _doctorSearchQuery = val),
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textDark),
            decoration: InputDecoration(
              hintText: 'Search by phone, city/location, pincode, dentist name...',
              hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.primaryBlue),
              suffixIcon: _doctorSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textMuted),
                      onPressed: () {
                        _doctorSearchController.clear();
                        setState(() => _doctorSearchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(0, 'All Platform Dentists (${allDocs.length})'),
                const SizedBox(width: 6),
                _buildFilterChip(1, '📍 Location & PIN Matches (${locationMatches.length})'),
                const SizedBox(width: 6),
                _buildFilterChip(2, '🗣️ Language Matches (${languageMatches.length})'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (displayedDoctors.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.search_off_rounded, size: 32, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 6),
                  Text(
                    _doctorSearchQuery.isNotEmpty
                        ? 'No dentists found matching "$_doctorSearchQuery"'
                        : 'No dentists match this filter.',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  TextButton(
                    onPressed: () {
                      _doctorSearchController.clear();
                      setState(() {
                        _doctorSearchQuery = '';
                        _selectedDoctorFilterIndex = 0;
                      });
                    },
                    child: const Text('Show All Available Dentists', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedDoctors.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final doc = displayedDoctors[index];
                final String docKey = doc.id.isNotEmpty ? doc.id : doc.name;
                final bool isExpanded = _expandedDoctorIds.contains(docKey);
                final bool isCurrentlyAssignedToThisDoc = assignedDoctor != null && (assignedDoctor.id == doc.id || assignedDoctor.userId == doc.id || assignedDoctor.name == doc.name);

                final bool isSamePin = patientPin.isNotEmpty && doc.pincode.isNotEmpty && doc.pincode == patientPin;
                final bool isSameCity = patientCity.isNotEmpty && doc.city.isNotEmpty && doc.city.toLowerCase().contains(patientCity);
                final matchingLanguages = doc.languages.where((l) => patientLangs.contains(l.toLowerCase())).toList();

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCurrentlyAssignedToThisDoc ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isCurrentlyAssignedToThisDoc ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                      width: isCurrentlyAssignedToThisDoc ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Doctor Name, Specialty, Experience, and Action Button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                            backgroundImage: doc.photoBytes != null ? MemoryImage(doc.photoBytes!) : null,
                            child: doc.photoBytes == null
                                ? Text(
                                    doc.name.isNotEmpty ? doc.name.replaceAll('Dr. ', '').trim()[0].toUpperCase() : 'D',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '${doc.specialty} • ${doc.qualification}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '⭐ ${doc.rating.toStringAsFixed(1)} • ${doc.experienceYears} Yrs Exp • Fee: ${doc.consultationFee.isNotEmpty ? doc.consultationFee : "₹500"}',
                                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isCurrentlyAssignedToThisDoc)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF86EFAC)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF15803D)),
                                  SizedBox(width: 3),
                                  Text('Assigned', style: TextStyle(color: Color(0xFF15803D), fontSize: 10.5, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            )
                          else
                            ElevatedButton.icon(
                              icon: const Icon(Icons.person_add_alt_1_rounded, size: 13),
                              label: Text(assignedDoctor != null ? 'Reassign' : 'Assign', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                elevation: 0,
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => _handleAssignDirectly(doc, req),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Location, Clinic, and Contact Details (Always Visible in Compact Mode)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.local_hospital_outlined, size: 12, color: AppTheme.textMuted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${doc.clinicName.isNotEmpty ? doc.clinicName : "DentaGuru Care Clinic"}${doc.clinicAddress.isNotEmpty ? " • ${doc.clinicAddress}" : ""}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 12, color: AppTheme.textMuted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'City: ${doc.city.isNotEmpty ? doc.city : "Hyderabad"} • Pincode: ${doc.pincode.isNotEmpty ? doc.pincode : "500001"}',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.translate_rounded, size: 12, color: AppTheme.textMuted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Languages: ${doc.languages.isNotEmpty ? doc.languages.join(", ") : "English, Telugu, Hindi"}',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (doc.phone.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(Icons.phone_rounded, size: 12, color: AppTheme.textMuted),
                                  const SizedBox(width: 4),
                                  Text('Mobile: ${doc.phone}', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                                  if (doc.email.isNotEmpty) ...[
                                    const SizedBox(width: 10),
                                    const Icon(Icons.email_outlined, size: 12, color: AppTheme.textMuted),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text('Email: ${doc.email}', style: const TextStyle(fontSize: 11, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Match Badges and View Details Toggle Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                if (isSamePin)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(4)),
                                    child: const Text('✓ Same PIN', style: TextStyle(color: Color(0xFF15803D), fontSize: 9.5, fontWeight: FontWeight.bold)),
                                  ),
                                if (isSameCity)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                                    child: const Text('✓ Same City', style: TextStyle(color: AppTheme.primaryBlue, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                  ),
                                if (matchingLanguages.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(4)),
                                    child: Text('✓ ${matchingLanguages.join(", ")}', style: const TextStyle(color: Color(0xFF7E22CE), fontSize: 9.5, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedDoctorIds.remove(docKey);
                                } else {
                                  _expandedDoctorIds.add(docKey);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isExpanded ? 'Hide Details' : 'View Details',
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                    size: 13,
                                    color: AppTheme.primaryBlue,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      // EXPANDED DENTIST DETAILS SECTION
                      if (isExpanded) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        const SizedBox(height: 8),
                        _buildDetailRow(Icons.school_outlined, 'Qualification', doc.qualification),
                        _buildDetailRow(Icons.timeline_rounded, 'Experience', '${doc.experienceYears} Years in Clinical Practice'),
                        if (doc.clinicAddress.isNotEmpty)
                          _buildDetailRow(Icons.location_city_rounded, 'Clinic Address', doc.clinicAddress),
                        _buildDetailRow(Icons.payments_outlined, 'Consultation Fee', doc.consultationFee.isNotEmpty ? doc.consultationFee : '₹500'),
                        _buildDetailRow(Icons.event_available_rounded, 'Availability', doc.status),
                        _buildDetailRow(Icons.verified_user_rounded, 'Verification Status', doc.verificationStatus),
                        if (doc.nextAvailableSlots.isNotEmpty)
                          _buildDetailRow(Icons.schedule_rounded, 'Next Slots', doc.nextAvailableSlots.join(', ')),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(int index, String label) {
    final isSelected = _selectedDoctorFilterIndex == index;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? Colors.white : const Color(0xFF334155))),
      selected: isSelected,
      selectedColor: AppTheme.primaryBlue,
      backgroundColor: const Color(0xFFF1F5F9),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      onSelected: (_) => setState(() => _selectedDoctorFilterIndex = index),
    );
  }

  // ==========================================
  // CARD 4: COMPLETE PATIENT PROFILE CARD
  // ==========================================
  Widget _buildPatientProfileDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, size: 17, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Patient Profile Information',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: () => setState(() => _isPatientDetailsExpanded = !_isPatientDetailsExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isPatientDetailsExpanded ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 12,
                        color: AppTheme.primaryBlue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isPatientDetailsExpanded ? 'Hide Details' : 'View Details',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _isPatientDetailsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 13,
                        color: AppTheme.primaryBlue,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),

          // Primary Summary Fields (Always Visible)
          _buildDetailRow(Icons.person_outline_rounded, 'Full Name', widget.patient.name.isNotEmpty ? widget.patient.name : 'Patient'),
          _buildDetailRow(Icons.phone_android_rounded, 'Mobile Number', widget.patient.phone.isNotEmpty ? widget.patient.phone : 'Not provided'),
          _buildDetailRow(Icons.location_city_rounded, 'City / Location', '${widget.patient.city.isNotEmpty && widget.patient.city != "--" ? widget.patient.city : "Not provided"}${widget.patient.pincode.isNotEmpty && widget.patient.pincode != "--" ? " • PIN: ${widget.patient.pincode}" : ""}'),

          // Complete Details (When Clicked "View Details")
          if (_isPatientDetailsExpanded) ...[
            _buildDetailRow(Icons.email_outlined, 'Email Address', widget.patient.email.isNotEmpty && widget.patient.email != '--' ? widget.patient.email : 'Not provided'),
            _buildDetailRow(Icons.cake_outlined, 'Age', widget.patient.age.isNotEmpty ? '${widget.patient.age} years' : 'Not specified'),
            _buildDetailRow(Icons.wc_rounded, 'Gender', widget.patient.gender.isNotEmpty ? widget.patient.gender : 'Not specified'),
            _buildDetailRow(Icons.bloodtype_outlined, 'Blood Group', widget.patient.bloodGroup.isNotEmpty ? widget.patient.bloodGroup : 'Not specified'),
            if (widget.patient.address.isNotEmpty)
              _buildDetailRow(Icons.home_outlined, 'Full Address', widget.patient.address),
            _buildDetailRow(
              Icons.translate_rounded,
              'Languages Preferred',
              widget.patient.languages.isNotEmpty ? widget.patient.languages.join(', ') : 'English',
            ),
            if (widget.patient.emergencyContact.isNotEmpty)
              _buildDetailRow(Icons.contact_phone_outlined, 'Emergency Contact', widget.patient.emergencyContact),
            _buildDetailRow(Icons.check_circle_outline_rounded, 'Patient Status', 'Active'),
          ],
        ],
      ),
    );
  }

  // ==========================================
  // CARD 5: PROBLEM & DENTAL COMPLAINT CARD
  // ==========================================
  Widget _buildProblemComplaintCard(PatientConsultationRequest? req) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.healing_rounded, size: 17, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Reported Problem / Dental Complaint',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              if (req != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    req.severity.isNotEmpty ? req.severity : 'Reported',
                    style: const TextStyle(color: Color(0xFFB45309), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),

          if (req != null) ...[
            _buildDetailRow(Icons.category_rounded, 'Problem Category', req.problemCategory.isNotEmpty ? req.problemCategory : 'General Dental Checkup'),
            _buildDetailRow(Icons.description_outlined, 'Problem Description', req.problemDescription.isNotEmpty ? req.problemDescription : 'Regular consultation requested.'),
            if (req.symptoms.isNotEmpty)
              _buildDetailRow(Icons.sick_outlined, 'Symptoms', req.symptoms),
            _buildDetailRow(Icons.calendar_today_outlined, 'Submission Date', _formatDateTime(req.submittedAt)),
            _buildDetailRow(Icons.info_outline_rounded, 'Request Status', req.status),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.textMuted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No open problem reports logged for this patient. Patient is currently registered in active directory.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Helper widget for clean field rows with strict text wrap safety
  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : 'Not provided',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark),
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}
