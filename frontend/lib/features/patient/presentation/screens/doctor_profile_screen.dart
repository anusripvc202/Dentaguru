import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/doctor_availability.dart';
import '../../../../core/models/medical_specialty_model.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../admin/presentation/widgets/doctor_slot_management_dialog.dart';

class DoctorProfileScreen extends StatefulWidget {
  final DoctorModel doctor;
  final bool isAdminView;
  final bool isClinicView;
  final VoidCallback? onAdminEditDoctor;
  final VoidCallback? onAdminDeleteDoctor;
  final VoidCallback? onAdminAssignDoctor;
  final VoidCallback? onClinicRemoveDoctor;

  const DoctorProfileScreen({
    super.key,
    required this.doctor,
    this.isAdminView = false,
    this.isClinicView = false,
    this.onAdminEditDoctor,
    this.onAdminDeleteDoctor,
    this.onAdminAssignDoctor,
    this.onClinicRemoveDoctor,
  });

  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  final PatientProblemService _patientService = PatientProblemService();

  late DateTime _selectedDate;
  late List<DateTime> _availableDates;
  final Map<String, DoctorAvailabilityModel> _configuredDateMap = {};

  DoctorAvailabilityModel? _currentAvailability;
  bool _isLoadingSlots = false;
  String? _selectedTimeSlot;

  String _selectedTreatment = 'General Consultation';
  final TextEditingController _symptomsController = TextEditingController();
  bool _isBooking = false;
  Map<String, String>? _lastConfirmedBooking;

  static const Color _successGreen = Color(0xFF10B981);
  static const LinearGradient _primaryGradient = LinearGradient(
    colors: [AppTheme.primaryBlue, AppTheme.primaryBlueDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  List<String> get _treatmentOptions {
    final options = MedicalSpecialtyModel.getConsultationTypesForSpecialty(
      widget.doctor.specialty,
      specialties: _patientService.specialties,
    );
    if (!options.contains(_selectedTreatment)) {
      return [_selectedTreatment, ...options];
    }
    return options;
  }

  static const List<String> _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> _monthNames = [
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

  String get _effectiveDoctorId {
    if (widget.doctor.id.trim().isNotEmpty) return widget.doctor.id.trim();
    if (widget.doctor.userId.trim().isNotEmpty) return widget.doctor.userId.trim();
    return widget.doctor.email.trim();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _selectedDate = today;
    _availableDates = List.generate(
      14,
      (index) => today.add(Duration(days: index)),
    );
    _patientService.addListener(_onServiceChanged);
    _initializeAvailability();
  }

  @override
  void dispose() {
    _patientService.removeListener(_onServiceChanged);
    _symptomsController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _formatDateIso(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatReadableDate(DateTime date) {
    final dayName = _weekdayNames[date.weekday - 1];
    final monthName = _monthNames[date.month - 1];
    return '$dayName, ${date.day} $monthName ${date.year}';
  }

  Future<void> _initializeAvailability() async {
    await _loadConfiguredDates();
    await _loadAvailabilityForDate(_selectedDate);
  }

  Future<void> _loadConfiguredDates() async {
    try {
      final list = await _patientService.getDoctorConfiguredAvailabilities(_effectiveDoctorId);
      if (!mounted) return;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      setState(() {
        for (final item in list) {
          if (item.date.isNotEmpty) {
            _configuredDateMap[item.date] = item;
            final parsed = DateTime.tryParse(item.date);
            if (parsed != null) {
              final cleanDate = DateTime(parsed.year, parsed.month, parsed.day);
              if (!cleanDate.isBefore(today)) {
                final exists = _availableDates.any(
                  (d) => d.year == cleanDate.year && d.month == cleanDate.month && d.day == cleanDate.day,
                );
                if (!exists) {
                  _availableDates.add(cleanDate);
                }
              }
            }
          }
        }
        _availableDates.sort((a, b) => a.compareTo(b));
      });
    } catch (_) {}
  }

  Future<void> _loadAvailabilityForDate(DateTime date) async {
    if (!mounted) return;
    setState(() {
      _isLoadingSlots = true;
      _selectedTimeSlot = null;
    });

    try {
      final avail = await _patientService.getDoctorAvailability(_effectiveDoctorId, date);
      if (!mounted) return;
      setState(() {
        _currentAvailability = avail;
        _configuredDateMap[_formatDateIso(date)] = avail;
        _isLoadingSlots = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingSlots = false;
      });
    }
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryBlue,
              onPrimary: Colors.white,
              onSurface: AppTheme.textDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      final cleanPicked = DateTime(picked.year, picked.month, picked.day);
      setState(() {
        final exists = _availableDates.any(
          (d) => d.year == cleanPicked.year && d.month == cleanPicked.month && d.day == cleanPicked.day,
        );
        if (!exists) {
          _availableDates.add(cleanPicked);
          _availableDates.sort((a, b) => a.compareTo(b));
        }
        _selectedDate = cleanPicked;
      });
      await _loadAvailabilityForDate(cleanPicked);
    }
  }

  String _buildDoctorBio(DoctorModel doc) {
    if (doc.bio.trim().isNotEmpty) {
      return doc.bio.trim();
    }
    final parts = <String>[];
    final expText = doc.experienceYears > 0 ? '${doc.experienceYears}+ years of clinical experience' : 'extensive clinical experience';
    final specText = doc.specialty.trim().isNotEmpty ? doc.specialty.trim() : 'General Dentistry';
    final qualText = doc.qualification.trim().isNotEmpty ? ' (${doc.qualification.trim()})' : '';
    parts.add('${doc.name}$qualText is a verified $specText specialist with $expText.');

    if (doc.clinicName.trim().isNotEmpty) {
      final loc = doc.city.trim().isNotEmpty ? ' in ${doc.city.trim()}' : '';
      parts.add('Currently practicing at ${doc.clinicName.trim()}$loc.');
    } else if (doc.city.trim().isNotEmpty) {
      parts.add('Providing comprehensive $specText care in ${doc.city.trim()}.');
    }

    if (doc.languages.isNotEmpty) {
      parts.add('Consultations available in ${doc.languages.join(', ')}.');
    }
    return parts.join(' ');
  }

  Future<void> _handleBookAppointment() async {
    if (_isBooking) return;

    final selectedSlot = _selectedTimeSlot;
    if (selectedSlot == null || selectedSlot.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an available time slot before booking.'),
          backgroundColor: AppTheme.brandOrange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final avail = _currentAvailability;
    if (avail != null) {
      final isBooked = avail.bookedSlots.any((b) => b.toLowerCase() == selectedSlot.toLowerCase());
      if (avail.isBlocked || isBooked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This time slot is not available. Please select an available slot.'),
            backgroundColor: AppTheme.statusCancelText,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() => _isBooking = true);

    try {
      final dateStr = _formatDateIso(_selectedDate);
      final res = await _patientService.bookAppointment(
        dentistId: _effectiveDoctorId,
        clinicId: widget.doctor.clinicName,
        date: dateStr,
        timeSlot: selectedSlot,
        treatment: _selectedTreatment,
        symptoms: _symptomsController.text.trim(),
      );

      if (!mounted) return;

      if (res['success'] == true) {
        final readableDate = _formatReadableDate(_selectedDate);
        setState(() {
          _isBooking = false;
          _lastConfirmedBooking = {
            'doctorName': widget.doctor.name,
            'specialty': widget.doctor.specialty,
            'clinic': widget.doctor.clinicName,
            'date': readableDate,
            'timeSlot': selectedSlot,
            'treatment': _selectedTreatment,
          };
          _selectedTimeSlot = null;
        });

        await _loadAvailabilityForDate(_selectedDate);
        if (!mounted) return;
        _showBookingSuccessDialog(
          doctorName: widget.doctor.name,
          dateLabel: readableDate,
          timeSlot: selectedSlot,
          treatment: _selectedTreatment,
        );
      } else {
        setState(() => _isBooking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message']?.toString() ?? 'Unable to book appointment. Please try another slot.'),
            backgroundColor: AppTheme.statusCancelText,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _loadAvailabilityForDate(_selectedDate);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBooking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to book appointment: $e'),
          backgroundColor: AppTheme.statusCancelText,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showBookingSuccessDialog({
    required String doctorName,
    required String dateLabel,
    required String timeSlot,
    required String treatment,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _successGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: _successGreen,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Appointment Booked!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your appointment with $doctorName has been scheduled.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textMedium,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildConfirmationDetailRow(Icons.person_rounded, 'Doctor', doctorName),
                  const SizedBox(height: 8),
                  _buildConfirmationDetailRow(Icons.calendar_today_rounded, 'Date', dateLabel),
                  const SizedBox(height: 8),
                  _buildConfirmationDetailRow(Icons.access_time_filled_rounded, 'Time Slot', timeSlot),
                  const SizedBox(height: 8),
                  _buildConfirmationDetailRow(Icons.medical_services_rounded, 'Consultation', treatment),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Done',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryBlue),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMedium,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final latestDoc = _patientService.allDoctors.cast<DoctorModel?>().firstWhere(
          (d) => d != null && (d.id == widget.doctor.id || (widget.doctor.userId.isNotEmpty && d.userId == widget.doctor.userId)),
          orElse: () => null,
        ) ??
        widget.doctor;
    final doc = latestDoc;
    final isFav = _patientService.isDoctorAdded(doc.id.isNotEmpty ? doc.id : doc.userId);
    final isAvailableStatus = doc.status.trim().toLowerCase() == 'available';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leadingWidth: 110,
        leading: InkWell(
          key: const Key('back_to_find_doctors_button'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppTheme.textDark),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Back',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        title: Text(
          widget.isAdminView
              ? 'Doctor Profile (Admin)'
              : (widget.isClinicView ? 'Doctor Profile' : 'Doctor Details'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
          ),
        ),
        actions: [
          if (!widget.isAdminView && !widget.isClinicView)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                tooltip: isFav ? 'Remove from Favourites' : 'Add to Favourites',
                onPressed: () async {
                  if (isFav) {
                    await _patientService.removeDoctorFromMyDoctors(doc);
                  } else {
                    await _patientService.addDoctorToMyDoctors(doc);
                  }
                },
                icon: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFav ? AppTheme.statusCancelText : AppTheme.textMedium,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDoctorHeroCard(doc, isAvailableStatus, isFav),
                  if (widget.isAdminView) ...[
                    const SizedBox(height: 18),
                    _buildAdminManagementCard(doc),
                  ] else if (widget.isClinicView) ...[
                    const SizedBox(height: 18),
                    _buildClinicManagementCard(doc),
                  ],
                  const SizedBox(height: 18),
                  _buildAboutAndCredentialsCard(doc),
                  const SizedBox(height: 18),
                  _buildClinicAndContactCard(doc),
                  const SizedBox(height: 18),
                  if (_lastConfirmedBooking != null) ...[
                    _buildConfirmedBookingBanner(_lastConfirmedBooking!),
                    const SizedBox(height: 18),
                  ],
                  _buildAppointmentAvailabilitySection(doc),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDoctorHeroCard(DoctorModel doc, bool isAvailableStatus, bool isFav) {
    final cleanName = doc.name.replaceAll('Dr. ', '').replaceAll('Dr.', '').trim();
    final initial = cleanName.isNotEmpty ? cleanName[0].toUpperCase() : 'D';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Circular Doctor Profile Image
              Stack(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: doc.photoBytes == null ? _primaryGradient : null,
                      image: doc.photoBytes != null
                          ? DecorationImage(
                              image: MemoryImage(doc.photoBytes!),
                              fit: BoxFit.cover,
                            )
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.16),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: doc.photoBytes == null
                        ? Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        size: 18,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Doctor Name, Specialization, Qualification & Status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            doc.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isAvailableStatus
                                ? _successGreen.withValues(alpha: 0.1)
                                : AppTheme.brandOrange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            doc.status.isNotEmpty ? doc.status : 'Available',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isAvailableStatus ? _successGreen : AppTheme.brandOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        doc.specialty.isNotEmpty ? doc.specialty : 'General Dentistry',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryBlue,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (doc.qualification.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.school_rounded, size: 15, color: AppTheme.textMedium),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              doc.qualification,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
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
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 16),
          // Key metrics strip: Experience, Rating, Consultation Fee
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildMetricPill(
                icon: Icons.workspace_premium_rounded,
                iconColor: AppTheme.primaryBlue,
                label: 'Experience',
                value: '${doc.experienceYears}+ Years',
              ),
              _buildMetricPill(
                icon: Icons.star_rounded,
                iconColor: Colors.amber.shade700,
                label: 'Rating',
                value: '${doc.rating.toStringAsFixed(1)} (${doc.reviewCount} reviews)',
              ),
              if (doc.consultationFee.trim().isNotEmpty)
                _buildMetricPill(
                  icon: Icons.payments_outlined,
                  iconColor: _successGreen,
                  label: 'Consultation Fee',
                  value: doc.consultationFee,
                ),
            ],
          ),
          if (!widget.isAdminView && !widget.isClinicView) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                if (isFav) {
                  await _patientService.removeDoctorFromMyDoctors(doc);
                } else {
                  await _patientService.addDoctorToMyDoctors(doc);
                }
              },
              icon: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 16,
                color: isFav ? AppTheme.statusCancelText : AppTheme.primaryBlue,
              ),
              label: Text(
                isFav ? 'Added to Favourites' : 'Add Favourite Doctor',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isFav ? AppTheme.textDark : AppTheme.primaryBlue,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: isFav ? Colors.grey.shade300 : AppTheme.primaryBlue.withValues(alpha: 0.4),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricPill({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMedium,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutAndCredentialsCard(DoctorModel doc) {
    final bioText = _buildDoctorBio(doc);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primaryBlue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'About the Doctor',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            bioText,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppTheme.textMedium,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (doc.qualification.trim().isNotEmpty)
                _buildInfoChip(Icons.school_outlined, 'Qualification: ${doc.qualification}'),
              _buildInfoChip(Icons.work_outline_rounded, 'Experience: ${doc.experienceYears} Years'),
              if (doc.licenseNumber.trim().isNotEmpty)
                _buildInfoChip(Icons.badge_outlined, 'Reg ID: ${doc.licenseNumber}'),
              if (doc.languages.isNotEmpty)
                _buildInfoChip(Icons.translate_rounded, 'Languages: ${doc.languages.join(', ')}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryBlue),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicAndContactCard(DoctorModel doc) {
    final locationParts = <String>[
      if (doc.city.trim().isNotEmpty) doc.city.trim(),
      if (doc.state.trim().isNotEmpty) doc.state.trim(),
      if (doc.pincode.trim().isNotEmpty) doc.pincode.trim(),
    ];
    final cityLine = locationParts.join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_hospital_outlined, size: 18, color: AppTheme.primaryBlue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Clinic & Contact Information',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildContactRow(
            icon: Icons.business_rounded,
            label: 'Clinic Name',
            value: doc.clinicName.trim().isNotEmpty ? doc.clinicName.trim() : 'Independent Dental Practice',
          ),
          if (doc.clinicAddress.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildContactRow(
              icon: Icons.place_outlined,
              label: 'Clinic Address',
              value: doc.clinicAddress.trim(),
            ),
          ],
          if (cityLine.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildContactRow(
              icon: Icons.location_city_rounded,
              label: 'City / Location',
              value: cityLine,
            ),
          ],
          if (doc.phone.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildContactRow(
              icon: Icons.phone_outlined,
              label: 'Contact Number',
              value: doc.phone.trim(),
            ),
          ],
          if (doc.email.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildContactRow(
              icon: Icons.email_outlined,
              label: 'Email Address',
              value: doc.email.trim(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdminManagementCard(DoctorModel doc) {
    return Container(
      key: const Key('admin_doctor_management_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primaryBlue, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Doctor Management & Verification',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Manage doctor credentials, verification status, consultation slots, or remove from platform',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.textMedium),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (widget.onAdminEditDoctor != null)
                ElevatedButton.icon(
                  key: const Key('admin_edit_doctor_button'),
                  onPressed: widget.onAdminEditDoctor,
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text('Edit Profile & Verification', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              OutlinedButton.icon(
                key: const Key('admin_configure_slots_button'),
                onPressed: () async {
                  await DoctorSlotManagementDialog.show(context, initialDoctor: doc);
                  if (mounted) {
                    await _initializeAvailability();
                  }
                },
                icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                label: const Text('Manage Availability Slots', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryBlue,
                  side: const BorderSide(color: AppTheme.primaryBlue),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (widget.onAdminAssignDoctor != null)
                OutlinedButton.icon(
                  key: const Key('admin_assign_doctor_button'),
                  onPressed: widget.onAdminAssignDoctor,
                  icon: const Icon(Icons.recommend_rounded, size: 16),
                  label: const Text('Suggest Doctor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _successGreen,
                    side: const BorderSide(color: _successGreen),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              if (widget.onAdminDeleteDoctor != null)
                OutlinedButton.icon(
                  key: const Key('admin_delete_doctor_button'),
                  onPressed: widget.onAdminDeleteDoctor,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Remove Doctor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClinicManagementCard(DoctorModel doc) {
    final isAvailable = doc.status.toLowerCase() == 'available';

    return Container(
      key: const Key('clinic_doctor_management_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medical_services_rounded, color: Color(0xFF0D9488), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clinic Doctor Management',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Manage doctor details, configure availability slots, toggle status, or remove from clinic',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.textMedium),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (widget.onAdminEditDoctor != null)
                ElevatedButton.icon(
                  key: const Key('clinic_edit_doctor_button'),
                  onPressed: widget.onAdminEditDoctor,
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text('Edit Doctor Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              OutlinedButton.icon(
                key: const Key('clinic_configure_slots_button'),
                onPressed: () async {
                  await DoctorSlotManagementDialog.show(context, initialDoctor: doc);
                  if (mounted) {
                    await _initializeAvailability();
                  }
                },
                icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                label: const Text('Update Availability', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0D9488),
                  side: const BorderSide(color: Color(0xFF0D9488)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('clinic_toggle_doctor_status_button'),
                onPressed: () async {
                  final newStatus = isAvailable ? 'Inactive' : 'Available';
                  await _patientService.updateDoctorProfessionalProfile(
                    doctorId: doc.id,
                    status: newStatus,
                  );
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Doctor status updated to $newStatus')),
                    );
                  }
                },
                icon: Icon(isAvailable ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded, size: 16),
                label: Text(
                  isAvailable ? 'Deactivate Doctor' : 'Activate Doctor',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isAvailable ? Colors.orange.shade800 : _successGreen,
                  side: BorderSide(color: isAvailable ? Colors.orange.shade400 : _successGreen),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (widget.onClinicRemoveDoctor != null)
                OutlinedButton.icon(
                  key: const Key('clinic_remove_doctor_button'),
                  onPressed: widget.onClinicRemoveDoctor,
                  icon: const Icon(Icons.person_remove_rounded, size: 16),
                  label: const Text('Remove from Clinic', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppTheme.primaryBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMedium,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmedBookingBanner(Map<String, String> booking) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _successGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _successGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, color: _successGreen, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Appointment Confirmed',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _successGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Booked with ${booking['doctorName']} on ${booking['date']} at ${booking['timeSlot']} (${booking['treatment']}).',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentAvailabilitySection(DoctorModel doc) {
    final avail = _currentAvailability;
    final allSlots = avail?.allSlots ?? const <String>[];
    final availableSlots = avail?.availableSlots ?? const <String>[];
    final isBlocked = avail?.isBlocked ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header + Custom Date Picker Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.event_available_rounded, size: 20, color: AppTheme.primaryBlue),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Appointment Availability',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickCustomDate,
                icon: const Icon(Icons.calendar_month_rounded, size: 16),
                label: const Text('Pick Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryBlue,
                  side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Select an available date and time slot to book your appointment.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textMedium),
          ),
          const SizedBox(height: 16),

          // Step 1: Select Available Date
          const Text(
            'Select Available Date',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _availableDates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final date = _availableDates[index];
                final dateStr = _formatDateIso(date);
                final isSelected = date.year == _selectedDate.year &&
                    date.month == _selectedDate.month &&
                    date.day == _selectedDate.day;
                final configured = _configuredDateMap[dateStr];
                final isDateBlocked = configured?.isBlocked == true;

                return GestureDetector(
                  key: Key('date_chip_$dateStr'),
                  onTap: () {
                    setState(() => _selectedDate = date);
                    _loadAvailabilityForDate(date);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 68,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryBlue
                          : (isDateBlocked ? Colors.red.shade50 : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryBlue
                            : (isDateBlocked ? Colors.red.shade200 : Colors.grey.shade300),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _weekdayNames[date.weekday - 1],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.85)
                                : (isDateBlocked ? AppTheme.statusCancelText : AppTheme.textMedium),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? Colors.white
                                : (isDateBlocked ? AppTheme.statusCancelText : AppTheme.textDark),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isDateBlocked ? 'Blocked' : _monthNames[date.month - 1],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.9)
                                : (isDateBlocked ? AppTheme.statusCancelText : AppTheme.primaryBlue),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // Step 2: Time Slots Header & Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Available Time Slots (${_formatReadableDate(_selectedDate)})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!_isLoadingSlots && !isBlocked)
                Text(
                  '${availableSlots.length} available',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _successGreen,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _buildLegendIndicator(
                color: Colors.white,
                borderColor: AppTheme.primaryBlue.withValues(alpha: 0.4),
                label: 'Available',
              ),
              _buildLegendIndicator(
                color: AppTheme.primaryBlue,
                borderColor: AppTheme.primaryBlue,
                label: 'Selected',
              ),
              _buildLegendIndicator(
                color: Colors.grey.shade200,
                borderColor: Colors.grey.shade300,
                label: 'Booked',
              ),
              _buildLegendIndicator(
                color: Colors.red.shade50,
                borderColor: Colors.red.shade200,
                label: 'Unavailable',
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Time Slots Grid / States
          if (_isLoadingSlots)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (isBlocked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_busy_rounded, color: Colors.red.shade700, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unavailable on ${_formatReadableDate(_selectedDate)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.red.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          avail?.blockedReason?.isNotEmpty == true
                              ? avail!.blockedReason!
                              : 'Doctor is unavailable on this date. Please select another date.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (allSlots.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded, color: Colors.orange.shade800, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No appointment slots configured for this date. Please choose another date.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (availableSlots.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_busy_rounded, color: Colors.orange.shade800, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'All Slots Fully Booked',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'All published slots for this date have been booked. Please pick another date.',
                          style: TextStyle(fontSize: 11.5, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: availableSlots.map((slot) {
                final isSlotSelected = _selectedTimeSlot == slot;

                return InkWell(
                  key: Key('time_slot_$slot'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _selectedTimeSlot = slot;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSlotSelected ? AppTheme.primaryBlue : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSlotSelected
                            ? AppTheme.primaryBlue
                            : AppTheme.primaryBlue.withValues(alpha: 0.35),
                        width: isSlotSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSlotSelected ? Icons.check_circle_rounded : Icons.access_time_rounded,
                          size: 15,
                          color: isSlotSelected ? Colors.white : AppTheme.primaryBlue,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            slot,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isSlotSelected ? Colors.white : AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

          if (!widget.isAdminView && !widget.isClinicView) ...[
            const SizedBox(height: 20),

            // Step 3: Consultation Reason & Notes (Patient only)
            const Text(
              'Consultation Reason',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedTreatment,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              items: _treatmentOptions
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(
                        item,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedTreatment = val);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _symptomsController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Optional: Describe symptoms or notes for the doctor...',
                hintStyle: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Book Appointment Action Button (Patient only)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                key: const Key('book_appointment_button'),
                onPressed: (_isBooking || isBlocked || _selectedTimeSlot == null)
                    ? null
                    : _handleBookAppointment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: _isBooking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.calendar_today_rounded, size: 18),
                label: Text(
                  _isBooking
                      ? 'Booking Appointment...'
                      : (_selectedTimeSlot != null
                          ? 'Book Appointment ($_selectedTimeSlot)'
                          : 'Book Appointment'),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendIndicator({
    required Color color,
    required Color borderColor,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMedium,
          ),
        ),
      ],
    );
  }
}

