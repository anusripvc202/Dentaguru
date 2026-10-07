import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/models/referral_model.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import 'refer_patient_flow_dialog.dart';

class ReferredPatientsSheet extends StatefulWidget {
  const ReferredPatientsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ReferredPatientsSheet(),
    );
  }

  @override
  State<ReferredPatientsSheet> createState() => _ReferredPatientsSheetState();
}

class _ReferredPatientsSheetState extends State<ReferredPatientsSheet> {
  final PatientProblemService _patientService = PatientProblemService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'All'; // 'All', 'Pending', 'Accepted', 'Rejected'

  @override
  void initState() {
    super.initState();
    _patientService.syncReferralsFromApi();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _buildReferralWhatsAppMessage(PatientReferral ref) {
    DoctorModel? doc;
    for (final d in _patientService.allDoctors) {
      if (ref.doctorId.isNotEmpty && (d.id == ref.doctorId || d.userId == ref.doctorId)) {
        doc = d;
        break;
      }
      final cleanRefDoc = ref.doctorName.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
      final cleanD = d.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
      if (cleanRefDoc.isNotEmpty && cleanRefDoc != 'specialist' && cleanRefDoc != 'doctor' && (cleanD.contains(cleanRefDoc) || cleanRefDoc.contains(cleanD))) {
        doc = d;
        break;
      }
    }

    String rawDocName = '';
    if (doc != null && doc.name.trim().isNotEmpty && doc.name != 'Dr. Specialist' && doc.name != 'Doctor') {
      rawDocName = doc.name.trim();
    } else if (ref.doctorName.trim().isNotEmpty && ref.doctorName != 'Dr. Specialist' && ref.doctorName != 'Doctor') {
      rawDocName = ref.doctorName.trim();
    } else if (doc != null && doc.name.trim().isNotEmpty) {
      rawDocName = doc.name.trim();
    } else {
      rawDocName = ref.doctorName.trim().isNotEmpty ? ref.doctorName.trim() : 'Specialist Doctor';
    }

    while (rawDocName.toLowerCase().startsWith('dr. dr.') || 
           rawDocName.toLowerCase().startsWith('dr. dr ') || 
           rawDocName.toLowerCase().startsWith('dr dr ')) {
      rawDocName = rawDocName.substring(3).trim();
      if (rawDocName.startsWith('.')) rawDocName = rawDocName.substring(1).trim();
    }
    final docName = (rawDocName.toLowerCase().startsWith('dr.') || rawDocName.toLowerCase().startsWith('dr '))
        ? rawDocName
        : 'Dr. $rawDocName';

    final specialty = (doc?.specialty.isNotEmpty == true && doc!.specialty != 'General Dentistry')
        ? doc.specialty
        : (ref.requiredSpecialist.isNotEmpty ? ref.requiredSpecialist : (doc?.specialty ?? 'Dental Specialist'));
    final qual = (doc?.qualification.isNotEmpty == true && doc!.qualification != 'BDS, MDS') ? ' (${doc.qualification})' : '';
    final clinic = (doc?.clinicName.isNotEmpty == true && doc!.clinicName != 'DentaGuru Partner Clinic')
        ? doc.clinicName
        : (ref.doctorClinicName.isNotEmpty ? ref.doctorClinicName : (doc?.clinicName.isNotEmpty == true ? doc!.clinicName : ''));

    final locationParts = [
      if (doc?.clinicAddress.isNotEmpty == true) doc!.clinicAddress else if (ref.doctorLocation.isNotEmpty) ref.doctorLocation,
      if (doc?.city.isNotEmpty == true) doc!.city else if (ref.doctorCity.isNotEmpty) ref.doctorCity,
      if (doc?.pincode.isNotEmpty == true) 'PIN: ${doc!.pincode}' else if (ref.doctorPincode.isNotEmpty) 'PIN: ${ref.doctorPincode}',
    ].where((s) => s.trim().isNotEmpty).toList();

    final fullAddress = locationParts.join(', ');

    String mapUrl = '';
    if (doc != null && doc.latitude != null && doc.longitude != null) {
      mapUrl = 'https://maps.google.com/?q=${doc.latitude},${doc.longitude}';
    } else {
      final mapQueryParts = [
        if (clinic.isNotEmpty && clinic != 'DentaGuru Partner Clinic') clinic,
        if (doc?.clinicAddress.isNotEmpty == true) doc!.clinicAddress else if (ref.doctorLocation.isNotEmpty) ref.doctorLocation,
        if (doc?.city.isNotEmpty == true) doc!.city else if (ref.doctorCity.isNotEmpty) ref.doctorCity,
        if (doc?.pincode.isNotEmpty == true) doc!.pincode else if (ref.doctorPincode.isNotEmpty) ref.doctorPincode,
      ].where((s) => s.trim().isNotEmpty).toList();

      final mapQuery = mapQueryParts.join(', ');
      if (mapQuery.isNotEmpty) {
        mapUrl = 'https://maps.google.com/?q=${Uri.encodeComponent(mapQuery)}';
      }
    }

    final docPhone = (doc?.phone.isNotEmpty == true) ? doc!.phone : (ref.doctorPhone.isNotEmpty ? ref.doctorPhone : '');

    final buffer = StringBuffer();
    buffer.writeln('Hi ${ref.referredPatientName},');
    buffer.writeln();
    buffer.writeln('I have referred you to *$docName*$qual on DentaGuru for your dental care.');
    buffer.writeln();
    buffer.writeln('👨‍⚕️ *Doctor & Clinic Details:*');
    buffer.writeln('• *Doctor:* $docName');
    buffer.writeln('• *Specialty:* $specialty');
    if (clinic.isNotEmpty) buffer.writeln('• *Clinic:* $clinic');
    if (docPhone.isNotEmpty) buffer.writeln('• *Doctor Mobile:* +91 $docPhone');
    if (fullAddress.isNotEmpty) buffer.writeln('• *Address:* $fullAddress');
    if (mapUrl.isNotEmpty) buffer.writeln('• 📍 *Location Map:* $mapUrl');
    if (doc != null && doc.experienceYears > 0) buffer.writeln('• *Experience:* ${doc.experienceYears}+ Years (${doc.rating} ⭐)');
    if (ref.clinicalComplaint.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('📋 *Clinical Reason / Diagnosis:* ${ref.clinicalComplaint}');
    }
    buffer.writeln();
    buffer.writeln('You can reach out directly to the clinic or doctor to schedule your appointment. Wishing you the best dental care!');

    return buffer.toString();
  }

  Future<void> _confirmDeleteReferral(BuildContext context, PatientReferral ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 22),
            SizedBox(width: 8),
            Text('Delete Referral', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the referral for ${ref.referredPatientName} to ${ref.doctorName}? This action cannot be undone.',
          style: const TextStyle(fontSize: 13, color: AppTheme.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🗑️ Referral for ${ref.referredPatientName} deleted'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      await _patientService.deletePatientReferral(ref.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const primaryColor = Color(0xFF6366F1);

    return AnimatedBuilder(
      animation: _patientService,
      builder: (context, _) {
        final allCreated = _patientService.myCreatedPatientReferrals;
        final allReceived = _patientService.receivedForMePatientReferrals;
        final combinedList = [...allCreated, ...allReceived];

        // Filter based on search query
        final filteredList = combinedList.where((ref) {
          if (_statusFilter == 'Pending' && ref.status != 'Pending') return false;
          if (_statusFilter == 'Accepted' && ref.status != 'Accepted') return false;
          if (_statusFilter == 'Rejected' && ref.status != 'Rejected') return false;

          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          final patName = ref.referredPatientName.toLowerCase();
          final patMobile = ref.referredPatientMobile.toLowerCase();
          final docName = ref.doctorName.toLowerCase();
          final specialty = ref.requiredSpecialist.toLowerCase();
          final clinic = ref.doctorClinicName.toLowerCase();
          final city = ref.referredPatientCity.toLowerCase();
          final complaint = ref.clinicalComplaint.toLowerCase();

          return patName.contains(q) ||
              patMobile.contains(q) ||
              docName.contains(q) ||
              specialty.contains(q) ||
              clinic.contains(q) ||
              city.contains(q) ||
              complaint.contains(q);
        }).toList();

        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Top Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 6),
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.groups_rounded, color: primaryColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Referred Patients',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${combinedList.length}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'All patients referred to specialized dental care',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: isDark ? Colors.white60 : Colors.black54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Search Box & Action Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontWeight: FontWeight.w500,
                          ),
                          onChanged: (val) => setState(() => _searchQuery = val.trim()),
                          decoration: InputDecoration(
                            hintText: 'Search patient, doctor, phone, city...',
                            hintStyle: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 16),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                      label: const Text(
                        'Refer New',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        ReferPatientFlowDialog.show(context);
                      },
                    ),
                  ],
                ),
              ),

              // Filter Chips
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildFilterChip('All', combinedList.length, isDark),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        'Pending',
                        combinedList.where((r) => r.status == 'Pending').length,
                        isDark,
                        label: 'Doctor Reviewing',
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        'Accepted',
                        combinedList.where((r) => r.status == 'Accepted').length,
                        isDark,
                        label: 'Accepted',
                      ),
                      const SizedBox(width: 6),
                      _buildFilterChip(
                        'Rejected',
                        combinedList.where((r) => r.status == 'Rejected').length,
                        isDark,
                        label: 'Declined',
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 1, thickness: 1),

              // Referral Cards List
              Expanded(
                child: filteredList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.people_outline_rounded,
                                  size: 40,
                                  color: primaryColor,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No referrals matching "$_searchQuery"'
                                    : 'No referred patients found',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Try checking for typos or clear your search query.'
                                    : 'You haven\'t referred any patients yet. Help a friend or family member get connected to expert dentists.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16, color: Colors.white),
                                label: const Text(
                                  'Refer a Patient Now',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  ReferPatientFlowDialog.show(context);
                                },
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        itemCount: filteredList.length,
                        itemBuilder: (context, index) {
                          final ref = filteredList[index];
                          return _buildReferralCard(ref, isDark);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String key, int count, bool isDark, {String? label}) {
    final isSelected = _statusFilter == key;
    final displayLabel = label ?? key;

    return InkWell(
      onTap: () => setState(() => _statusFilter = key),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1).withValues(alpha: 0.14)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayLabel,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF6366F1)
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF6366F1) : (isDark ? Colors.white24 : Colors.black12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferralCard(PatientReferral ref, bool isDark) {
    final isAccepted = ref.status == 'Accepted';
    final isRejected = ref.status == 'Rejected';

    final statusColor = isAccepted
        ? const Color(0xFF10B981)
        : (isRejected ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
    final statusBg = isAccepted
        ? const Color(0xFFDCFCE7)
        : (isRejected ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7));
    final statusText = isAccepted
        ? '🟢 Accepted by Doctor'
        : (isRejected ? '🔴 Referral Declined' : '🟡 Doctor Reviewing');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAccepted
              ? const Color(0xFF86EFAC)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.12),
                      child: Text(
                        ref.referredPatientName.isNotEmpty
                            ? ref.referredPatientName[0].toUpperCase()
                            : 'P',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ref.referredPatientName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            [
                              '+91 ${ref.referredPatientMobile}',
                              if (ref.referredPatientAge.isNotEmpty) '${ref.referredPatientAge} Yrs',
                              if (ref.referredPatientGender.isNotEmpty) ref.referredPatientGender,
                            ].join(' • '),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (ref.referredPatientLocation.isNotEmpty ||
                              ref.referredPatientCity.isNotEmpty ||
                              ref.referredPatientPincode.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF0284C7)),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    [
                                      if (ref.referredPatientLocation.isNotEmpty) ref.referredPatientLocation,
                                      if (ref.referredPatientCity.isNotEmpty) ref.referredPatientCity,
                                      if (ref.referredPatientPincode.isNotEmpty) '(${ref.referredPatientPincode})',
                                    ].join(', '),
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF0369A1),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    tooltip: 'Delete Referral',
                    onPressed: () => _confirmDeleteReferral(context, ref),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, thickness: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(Icons.medical_services_outlined, size: 14, color: Color(0xFF0D9488)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${ref.doctorName} • ${ref.requiredSpecialist}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.local_hospital_outlined, size: 14, color: isDark ? Colors.white54 : Colors.black45),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    ref.doctorClinicName.isNotEmpty ? ref.doctorClinicName : 'DentaGuru Partner Clinic',
                    if (ref.doctorLocation.isNotEmpty || ref.doctorCity.isNotEmpty || ref.doctorPincode.isNotEmpty)
                      [
                        if (ref.doctorLocation.isNotEmpty) ref.doctorLocation,
                        if (ref.doctorCity.isNotEmpty) ref.doctorCity,
                        if (ref.doctorPincode.isNotEmpty) ref.doctorPincode,
                      ].join(', ')
                  ].join(' • '),
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          if (ref.clinicalComplaint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: ${ref.clinicalComplaint}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white70 : Colors.black54,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          if (isRejected && ref.rejectionReason != null && ref.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Reason: ${ref.rejectionReason}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B), fontWeight: FontWeight.w500),
              ),
            ),
          ],

          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.chat_rounded, size: 13, color: Colors.white),
                label: Text(
                  'WhatsApp ${ref.referredPatientName}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: () async {
                  String rawPhone = ref.referredPatientMobile.replaceAll(RegExp(r'[^0-9]'), '');
                  if (rawPhone.startsWith('0') && rawPhone.length == 11) {
                    rawPhone = '91${rawPhone.substring(1)}';
                  } else if (rawPhone.length == 10) {
                    rawPhone = '91$rawPhone';
                  }
                  final msg = _buildReferralWhatsAppMessage(ref);
                  final waUrl = Uri.parse(rawPhone.isNotEmpty
                      ? 'https://wa.me/$rawPhone?text=${Uri.encodeComponent(msg)}'
                      : 'https://wa.me/?text=${Uri.encodeComponent(msg)}');
                  try {
                    await launchUrl(waUrl, mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
              ),
              Row(
                children: [
                  Text(
                    '${ref.referralDate.day}/${ref.referralDate.month}/${ref.referralDate.year}',
                    style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : Colors.black45),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _confirmDeleteReferral(context, ref),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.delete_outline_rounded, size: 13, color: Color(0xFFEF4444)),
                          SizedBox(width: 3),
                          Text(
                            'Delete',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
