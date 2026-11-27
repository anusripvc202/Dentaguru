import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/booking_rules_config.dart';
import '../../../../core/models/medical_specialty_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/models/doctor_availability.dart';
import '../../../../core/models/specialty_clinical_config.dart';

class BookVisitFlowDialog extends StatefulWidget {
  final DoctorModel? preselectedDoctor;
  final String? initialSpecialtyFilter;
  final String initialConsultationMode;
  final DateTime? initialDate;
  final String? initialTimeSlot;
  final Duration autoRefreshInterval;
  final bool enableAutoRefresh;
  final VoidCallback? onBookingSuccess;

  const BookVisitFlowDialog({
    super.key,
    this.preselectedDoctor,
    this.initialSpecialtyFilter,
    this.initialConsultationMode = 'In-Person',
    this.initialDate,
    this.initialTimeSlot,
    this.autoRefreshInterval = const Duration(seconds: 15),
    this.enableAutoRefresh = true,
    this.onBookingSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    DoctorModel? preselectedDoctor,
    String? initialSpecialtyFilter,
    String initialConsultationMode = 'In-Person',
    DateTime? initialDate,
    String? initialTimeSlot,
    Duration autoRefreshInterval = const Duration(seconds: 15),
    bool enableAutoRefresh = true,
    VoidCallback? onBookingSuccess,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BookVisitFlowDialog(
        preselectedDoctor: preselectedDoctor,
        initialSpecialtyFilter: initialSpecialtyFilter,
        initialConsultationMode: initialConsultationMode,
        initialDate: initialDate,
        initialTimeSlot: initialTimeSlot,
        autoRefreshInterval: autoRefreshInterval,
        enableAutoRefresh: enableAutoRefresh,
        onBookingSuccess: onBookingSuccess,
      ),
    );
  }

  @override
  State<BookVisitFlowDialog> createState() => _BookVisitFlowDialogState();
}

class _BookVisitFlowDialogState extends State<BookVisitFlowDialog> {
  final PatientProblemService _patientService = PatientProblemService();

  // Step state: 1: Select Doctor, 2: Date & Slot, 3: Reason, 4: Review, 5: Success
  int _currentStep = 1;

  // Step 1: Doctor Selection
  DoctorModel? _selectedDoctor;
  String _doctorSearchQuery = '';
  String _selectedSpecialtyFilter = 'All';

  // Step 2: Mode, Date & Slot
  late String _selectedConsultationMode; // 'In-Person' or 'Online'
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedTimeSlot;
  DoctorAvailabilityModel? _doctorAvailability;
  Map<String, DoctorAvailabilityModel> _configuredDateMap = {};
  bool _isLoadingSlots = false;

  // Step 3: Reason & Symptoms (dynamic per selected doctor's specialty)
  String _selectedCategory = 'Routine Medical Checkup';
  final TextEditingController _symptomsController = TextEditingController();
  String _selectedSeverity = 'Mild';

  // Step 4 & 5: Submission, Temporary Slot Lock & Earlier-Slot Preference Status
  bool _isSubmitting = false;
  bool _isAcquiringLock = false;
  String? _errorMessage;
  String? _slotRefreshNotice;
  bool _appliedInitialSlot = false;
  String? _selectedReleasedSlotId;
  SlotLockModel? _activeSlotLock;
  int _lockSecondsRemaining = 0;
  Timer? _lockCountdownTimer;
  bool _notifyEarlierSlots = false;
  bool _isSavingNotifPref = false;
  RealtimeChannel? _availabilityRealtimeChannel;
  Timer? _availabilityRefreshTimer;

  List<String> get _specialtyFilters => [
        'All',
        ...SpecialtyClinicalConfig.allSelectableSpecialties(
          activeSpecialties: _patientService.activeSpecialties,
          registeredDoctorSpecialties: _patientService.allDoctors.map((d) => d.specialty),
        ),
      ];

  SpecialtyClinicalProfile get _activeClinicalProfile {
    final targetSpec = _selectedDoctor?.specialty.trim().isNotEmpty == true
        ? _selectedDoctor!.specialty
        : (_selectedSpecialtyFilter != 'All' ? _selectedSpecialtyFilter : 'General Medicine');
    return SpecialtyClinicalConfig.forSpecialty(targetSpec);
  }

  List<String> get _categories {
    final list = List<String>.from(_activeClinicalProfile.triageCategories);
    if (!list.contains('Routine Medical Checkup')) {
      list.add('Routine Medical Checkup');
    }
    if (!list.contains('Other Medical Concern')) {
      list.add('Other Medical Concern');
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _selectedConsultationMode = widget.initialConsultationMode.toLowerCase().contains('online')
        ? 'Online'
        : 'In-Person';
    if (widget.initialDate != null) {
      _selectedDate = DateTime(widget.initialDate!.year, widget.initialDate!.month, widget.initialDate!.day);
    }
    if (widget.initialSpecialtyFilter != null && widget.initialSpecialtyFilter!.trim().isNotEmpty) {
      _selectedSpecialtyFilter = widget.initialSpecialtyFilter!.trim();
    }
    if (widget.preselectedDoctor != null && widget.preselectedDoctor!.isAvailable) {
      _selectedDoctor = widget.preselectedDoctor;
      _selectedCategory = _categories.first;
      _currentStep = 2; // Jump directly to Date & Slot if doctor preselected
      _loadDoctorAvailability();
    } else if (widget.preselectedDoctor != null && !widget.preselectedDoctor!.isAvailable) {
      _errorMessage = 'Doctor is currently unavailable and not accepting new bookings.';
      _currentStep = 1;
    }
    // Subscribe to Supabase Realtime updates with safe periodic refresh fallback
    _setupLiveAvailabilitySync();
    // Refresh live doctors in background
    _patientService.syncDoctorsFromApi();
  }

  void _setupLiveAvailabilitySync() {
    try {
      final channelName = 'booking_avail_${DateTime.now().microsecondsSinceEpoch}';
      _availabilityRealtimeChannel = Supabase.instance.client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'appointments',
            callback: (_) {
              if (mounted && _selectedDoctor != null && !_isSubmitting) {
                unawaited(_loadDoctorAvailability(silent: true));
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'doctor_availability',
            callback: (_) {
              if (mounted && _selectedDoctor != null && !_isSubmitting) {
                unawaited(_loadDoctorAvailability(silent: true));
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'released_slots',
            callback: (_) {
              if (mounted && _selectedDoctor != null && !_isSubmitting) {
                unawaited(_loadDoctorAvailability(silent: true));
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'doctor_scheduling_settings',
            callback: (_) {
              if (mounted && _selectedDoctor != null && !_isSubmitting) {
                unawaited(_loadDoctorAvailability(silent: true));
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'appointment_slot_locks',
            callback: (_) {
              if (mounted && _selectedDoctor != null && !_isSubmitting && _currentStep == 2) {
                unawaited(_loadDoctorAvailability(silent: true));
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Booking Realtime fallback notice: $e');
    }

    if (widget.enableAutoRefresh && widget.autoRefreshInterval > Duration.zero) {
      _availabilityRefreshTimer?.cancel();
      _availabilityRefreshTimer = Timer.periodic(widget.autoRefreshInterval, (_) {
        if (mounted && _currentStep == 2 && _selectedDoctor != null && !_isSubmitting && !_isLoadingSlots) {
          unawaited(_loadDoctorAvailability(silent: true));
        }
      });
    }
  }

  String _formatDateIsoLocal(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Future<void> _loadDoctorAvailability({bool silent = false}) async {
    if (_selectedDoctor == null) return;
    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;
    if (docId.isEmpty) return;

    final previousSelectedSlot = _selectedTimeSlot;
    if (!silent) {
      unawaited(_loadDoctorNotificationPreference(docId));
      setState(() {
        _isLoadingSlots = true;
        _selectedTimeSlot = null;
        _selectedReleasedSlotId = null;
        _slotRefreshNotice = null;
      });
    }

    try {
      final avail = await _patientService.getDoctorAvailability(
        docId,
        _selectedDate,
        consultationType: _selectedConsultationMode,
      );
      final blocked = await _patientService.getBlockedDates(docId);
      if (mounted) {
        setState(() {
          _doctorAvailability = avail;
          _configuredDateMap[_formatDateIsoLocal(_selectedDate)] = avail;
          for (final b in blocked) {
            if (b.date.isNotEmpty) {
              _configuredDateMap[b.date] = b;
            }
          }

          // Handle deep-linked initialTimeSlot on first availability load
          if (!_appliedInitialSlot &&
              widget.initialTimeSlot != null &&
              widget.initialTimeSlot!.trim().isNotEmpty) {
            _appliedInitialSlot = true;
            final targetSlot = widget.initialTimeSlot!.trim();
            final matchedSlot = avail.allSlots
                .where((s) => s.trim().toLowerCase() == targetSlot.toLowerCase())
                .firstOrNull;
            if (matchedSlot != null &&
                !avail.isBlocked &&
                !avail.bookedSlots.any((b) => b.trim().toLowerCase() == matchedSlot.trim().toLowerCase()) &&
                !avail.lockedSlots.any((l) => l.trim().toLowerCase() == matchedSlot.trim().toLowerCase()) &&
                !_isSlotBooked(matchedSlot)) {
              _selectedTimeSlot = matchedSlot;
              _selectedReleasedSlotId = _findReleasedSlotIdForTime(matchedSlot);
              _slotRefreshNotice = null;
            } else {
              _selectedTimeSlot = null;
              _selectedReleasedSlotId = null;
              _slotRefreshNotice = 'This slot is no longer available. Please select another time.';
            }
          } else if (silent && previousSelectedSlot != null && previousSelectedSlot.trim().isNotEmpty) {
            final stillInList = avail.allSlots.any(
              (s) => s.trim().toLowerCase() == previousSelectedSlot.trim().toLowerCase(),
            );
            final nowBooked = avail.isBlocked ||
                !stillInList ||
                avail.bookedSlots.any((b) => b.trim().toLowerCase() == previousSelectedSlot.trim().toLowerCase()) ||
                avail.lockedSlots.any((l) => l.trim().toLowerCase() == previousSelectedSlot.trim().toLowerCase()) ||
                _isSlotBooked(previousSelectedSlot);
            if (nowBooked) {
              _selectedTimeSlot = null;
              _selectedReleasedSlotId = null;
              _slotRefreshNotice = 'This slot is no longer available. Please select another time.';
            }
          }

          _isLoadingSlots = false;
        });
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() {
          _isLoadingSlots = false;
        });
      }
    }
  }

  Future<void> _loadDoctorNotificationPreference(String docId) async {
    try {
      final pref = await _patientService.getPatientDoctorPreference(docId);
      if (mounted && pref != null) {
        setState(() => _notifyEarlierSlots = pref.notifyEarlierSlots);
      }
    } catch (_) {}
  }

  Future<void> _toggleEarlierSlotNotification(bool enabled) async {
    if (_selectedDoctor == null || _isSavingNotifPref) return;
    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;
    if (docId.isEmpty) return;
    final prev = _notifyEarlierSlots;
    setState(() {
      _notifyEarlierSlots = enabled;
      _isSavingNotifPref = true;
    });
    final res = await _patientService.savePatientDoctorPreference(
      dentistId: docId,
      isFavorite: true,
      notifyEarlierSlots: enabled,
      preferredConsultationType: _selectedConsultationMode,
      preferredDate: _formatDateIsoLocal(_selectedDate),
    );
    if (!mounted) return;
    setState(() {
      _isSavingNotifPref = false;
      if (res['success'] != true) {
        _notifyEarlierSlots = prev;
      }
    });
  }

  String? _findReleasedSlotIdForTime(String slotStr) {
    final avail = _doctorAvailability;
    if (avail == null) return null;
    final norm = slotStr.trim().toLowerCase();
    for (final rel in avail.releasedSlots) {
      final t = (rel['startTime'] ?? rel['start_time'] ?? '').toString().trim().toLowerCase();
      if (t == norm) {
        final id = (rel['releasedSlotId'] ?? rel['id'] ?? '').toString().trim();
        if (id.isNotEmpty) return id;
      }
    }
    for (final item in avail.slotItems) {
      final t = (item['startTime'] ?? item['start_time'] ?? '').toString().trim().toLowerCase();
      if (t == norm && item['isReleasedSlot'] == true) {
        final id = (item['releasedSlotId'] ?? item['id'] ?? '').toString().trim();
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }

  void _startLockCountdown(SlotLockModel lock) {
    _lockCountdownTimer?.cancel();
    _activeSlotLock = lock;
    final secs = lock.remaining.inSeconds.clamp(0, 900);
    _lockSecondsRemaining = secs;
    _lockCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = _activeSlotLock?.remaining.inSeconds ?? 0;
      if (left <= 0) {
        timer.cancel();
        final expiredLockId = _activeSlotLock?.lockId;
        if (expiredLockId != null && expiredLockId.isNotEmpty) {
          unawaited(_patientService.releaseSlotLock(expiredLockId));
        }
        setState(() {
          _activeSlotLock = null;
          _lockSecondsRemaining = 0;
          _selectedTimeSlot = null;
          _selectedReleasedSlotId = null;
          if (_currentStep == 3 || _currentStep == 4) {
            _currentStep = 2;
          }
          _slotRefreshNotice = 'Your temporary slot reservation expired. Please select a time slot again.';
          _errorMessage = null;
        });
        unawaited(_loadDoctorAvailability(silent: true));
      } else {
        setState(() => _lockSecondsRemaining = left);
      }
    });
  }

  Future<void> _releaseActiveLock({bool silent = true}) async {
    _lockCountdownTimer?.cancel();
    final lockId = _activeSlotLock?.lockId;
    _activeSlotLock = null;
    _lockSecondsRemaining = 0;
    if (lockId != null && lockId.isNotEmpty) {
      try {
        await _patientService.releaseSlotLock(lockId);
      } catch (_) {}
    }
    if (!silent && mounted) setState(() {});
  }

  String _formatCountdown(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool _doctorSupportsConsultationMode(DoctorModel? doc, String mode) {
    if (doc == null) return true;
    final isOnline = mode.trim().toLowerCase() == 'online';
    return isOnline ? doc.onlineConsultationEnabled : doc.inPersonConsultationEnabled;
  }

  String _unsupportedModeErrorMessage(String mode) {
    if (mode.trim().toLowerCase() == 'online') {
      return 'This doctor does not offer Online consultations. Please select In-Person Consultation or choose an online-enabled doctor.';
    }
    return 'This doctor provides Online consultations only and is not available for In-Person clinic visits.';
  }

  Future<void> _acquireLockAndProceedToStep3() async {
    if (_selectedDoctor == null || _selectedTimeSlot == null || _isAcquiringLock) return;
    if (!_doctorSupportsConsultationMode(_selectedDoctor, _selectedConsultationMode)) {
      final msg = _unsupportedModeErrorMessage(_selectedConsultationMode);
      setState(() {
        _slotRefreshNotice = msg;
        _errorMessage = msg;
      });
      return;
    }
    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;
    final releasedId = _selectedReleasedSlotId ?? _findReleasedSlotIdForTime(_selectedTimeSlot!);

    setState(() {
      _isAcquiringLock = true;
      _slotRefreshNotice = null;
      _errorMessage = null;
    });

    final lockRes = await _patientService.acquireSlotLock(
      dentistId: docId,
      date: _selectedDate,
      timeSlot: _selectedTimeSlot!,
      consultationType: _selectedConsultationMode,
      releasedSlotId: releasedId,
    );

    if (!mounted) return;

    if (lockRes['success'] == true && (lockRes['lockId'] ?? '').toString().isNotEmpty) {
      final lockModel = SlotLockModel.fromJson(lockRes, fallbackDentistId: docId);
      setState(() {
        _isAcquiringLock = false;
        _selectedReleasedSlotId = releasedId;
        _currentStep = 3;
      });
      _startLockCountdown(lockModel);
      return;
    }

    final reason = (lockRes['reason'] ?? '').toString().toUpperCase();
    // Explicit conflict / lock / released-slot rejection -> keep on Step 2 and refresh live slots!
    if (releasedId != null ||
        reason == 'SLOT_LOCKED' ||
        reason == 'APPOINTMENT_CONFLICT' ||
        reason == 'RELEASED_SLOT_UNAVAILABLE' ||
        reason == 'RELEASED_SLOT_LOCK_REQUIRED' ||
        reason == 'DAILY_LIMIT_REACHED' ||
        reason == 'DATE_BLOCKED' ||
        reason == 'SLOT_BLOCKED' ||
        reason == 'OVERLAPS_BREAK' ||
        reason == 'OUTSIDE_WORKING_HOURS' ||
        reason == 'NON_WORKING_DAY' ||
        reason == 'CONSULTATION_TYPE_DISABLED') {
      setState(() {
        _isAcquiringLock = false;
        _selectedTimeSlot = null;
        _selectedReleasedSlotId = null;
        _slotRefreshNotice = lockRes['message']?.toString() ??
            'This slot is no longer available. Please select another time.';
      });
      unawaited(_loadDoctorAvailability(silent: true));
      return;
    }

    // Offline/unauthenticated local unit-test fallback for regular slots only
    setState(() {
      _isAcquiringLock = false;
      _currentStep = 3;
    });
  }

  @override
  void dispose() {
    _lockCountdownTimer?.cancel();
    if (_activeSlotLock != null && _currentStep < 5) {
      unawaited(_patientService.releaseSlotLock(_activeSlotLock!.lockId));
    }
    _availabilityRefreshTimer?.cancel();
    if (_availabilityRealtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_availabilityRealtimeChannel!);
      } catch (_) {}
    }
    _symptomsController.dispose();
    super.dispose();
  }

  // Helper to check if a specific time slot overlaps an active appointment (unified Online + In-Person calendar + buffer)
  bool _isSlotBooked(String slot) {
    if (_selectedDoctor == null) return false;
    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;
    final dateStr = _formatDateIsoLocal(_selectedDate);
    final candStart = BookingRulesConfig.parseClockSlotMinutes(slot);
    final candDur = BookingRulesConfig.durationForMode(_selectedConsultationMode);
    final candBuf = BookingRulesConfig.bufferForMode(_selectedConsultationMode);
    final candEnd = candStart != null ? candStart + candDur + candBuf : null;

    if (_doctorAvailability != null) {
      if (_doctorAvailability!.bookedSlots.any((b) => b.trim().toLowerCase() == slot.trim().toLowerCase())) {
        return true;
      }
      if (candStart != null && candEnd != null) {
        for (final b in _doctorAvailability!.blockedSlots) {
          final bStart = int.tryParse(b['startMin']?.toString() ?? '') ??
              BookingRulesConfig.parseClockSlotMinutes(b['startTime']?.toString() ?? b['slot']?.toString() ?? '');
          final bEnd = int.tryParse(b['endMin']?.toString() ?? '') ??
              BookingRulesConfig.parseClockSlotMinutes(b['endTime']?.toString() ?? '') ??
              (bStart != null ? bStart + BookingRulesConfig.defaultSlotIntervalMinutes : null);
          if (bStart != null && bEnd != null && BookingRulesConfig.intervalsOverlap(candStart, candStart + candDur, bStart, bEnd)) {
            return true;
          }
        }
        for (final occ in _doctorAvailability!.occupiedIntervals) {
          final oStart = int.tryParse(occ['startMin']?.toString() ?? '');
          final oEnd = int.tryParse(occ['occupiedEndMin']?.toString() ?? '');
          if (oStart != null && oEnd != null && BookingRulesConfig.intervalsOverlap(candStart, candEnd, oStart, oEnd)) {
            return true;
          }
        }
      }
    }

    for (final req in _patientService.requests) {
      final s = req.status.toUpperCase();
      if (s == 'CANCELLED' || s == 'REJECTED' || s == 'NO_SHOW') continue;
      final reqDocId = req.assignedDoctorId ?? '';
      final reqDate = req.confirmedDate?.split('T').first ?? '';
      final reqSlot = (req.confirmedTimeSlot ?? '').trim();

      if ((reqDocId == docId || req.assignedDoctorName == _selectedDoctor!.name) && reqDate == dateStr) {
        if (reqSlot.toLowerCase() == slot.toLowerCase()) {
          return true;
        }
        if (candStart != null && candEnd != null) {
          final existStart = BookingRulesConfig.parseClockSlotMinutes(reqSlot);
          if (existStart != null) {
            final existDur = req.durationMinutes ?? BookingRulesConfig.durationForMode(req.displayConsultationMode);
            final existBuf = req.bufferMinutes ?? BookingRulesConfig.bufferForMode(req.displayConsultationMode);
            final existEnd = existStart + existDur + existBuf + req.delayMinutes;
            if (BookingRulesConfig.intervalsOverlap(candStart, candEnd, existStart, existEnd)) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[dt.weekday - 1]}, ${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: _currentStep > 1 && _currentStep < 5
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textDark),
                    onPressed: () {
                      if (_currentStep == 3) {
                        unawaited(_releaseActiveLock());
                      }
                      setState(() {
                        if (_currentStep == 2 && widget.preselectedDoctor != null) {
                          Navigator.of(context).pop();
                        } else {
                          _currentStep--;
                          _errorMessage = null;
                        }
                      });
                    },
                  )
                : null,
            title: Text(
              _currentStep == 5
                  ? 'Booking Confirmed'
                  : 'Book Consultation ($_currentStep/4)',
              style: const TextStyle(
                color: AppTheme.textDark,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: LinearProgressIndicator(
                value: _currentStep / 5.0,
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                minHeight: 3,
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildCurrentStepView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 1:
        return _buildStep1SelectDoctor();
      case 2:
        return _buildStep2SelectDateAndSlot();
      case 3:
        return _buildStep3ReasonAndSymptoms();
      case 4:
        return _buildStep4ReviewAndConfirm();
      case 5:
        return _buildStep5Success();
      default:
        return const SizedBox.shrink();
    }
  }

  // ==========================================
  // STEP 1: SELECT DOCTOR
  // ==========================================
  Widget _buildStep1SelectDoctor() {
    final allDoctors = _patientService.availableDoctors;
    final strictOnlineFilter = widget.initialConsultationMode.trim().toLowerCase().contains('online');
    final filteredDoctors = allDoctors.where((doc) {
      if (strictOnlineFilter && !doc.onlineConsultationEnabled) {
        return false;
      }
      if (!strictOnlineFilter && _selectedConsultationMode == 'In-Person' && !doc.inPersonConsultationEnabled) {
        return false;
      }
      final matchesQuery = _doctorSearchQuery.isEmpty ||
          doc.name.toLowerCase().contains(_doctorSearchQuery.toLowerCase()) ||
          doc.specialty.toLowerCase().contains(_doctorSearchQuery.toLowerCase()) ||
          doc.clinicName.toLowerCase().contains(_doctorSearchQuery.toLowerCase());
      final matchesSpecialty = MedicalSpecialtyModel.matchesSpecialtyFilter(
        doc.specialty,
        _selectedSpecialtyFilter,
        specialties: _patientService.specialties,
      );
      return matchesQuery && matchesSpecialty;
    }).toList();

    return Column(
      children: [
        // Search & Filter header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search doctor, specialty, or clinic...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.textMuted),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
                onChanged: (val) => setState(() => _doctorSearchQuery = val.trim()),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _specialtyFilters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, idx) {
                    final spec = _specialtyFilters[idx];
                    final isSelected = _selectedSpecialtyFilter == spec;
                    return ChoiceChip(
                      label: Text(spec),
                      selected: isSelected,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : AppTheme.textDark,
                      ),
                      selectedColor: AppTheme.primaryBlue,
                      backgroundColor: const Color(0xFFF1F5F9),
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onSelected: (_) => setState(() => _selectedSpecialtyFilter = spec),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        // Doctor Cards List
        Expanded(
          child: filteredDoctors.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_search_rounded, size: 40, color: AppTheme.textMuted),
                        SizedBox(height: 8),
                        Text(
                          'No doctors found matching criteria',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Try clearing your search or selecting "All" specialties.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredDoctors.length,
                  itemBuilder: (context, idx) {
                    final doc = filteredDoctors[idx];
                    final isSelected = _selectedDoctor?.id == doc.id;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0x14012A58) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.5 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() {
                            _selectedDoctor = doc;
                            _selectedCategory = _categories.first;
                            _selectedTimeSlot = null; // reset slot on doctor change
                          });
                          _loadDoctorAvailability();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
                                child: Text(
                                  doc.name.isNotEmpty
                                      ? doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim()[0].toUpperCase()
                                      : 'D',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 16),
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
                                          child: Text(
                                            doc.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: AppTheme.textDark,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(Icons.check_circle_rounded, color: AppTheme.primaryBlue, size: 20),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0x14012A58),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            doc.specialty,
                                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF012A58)),
                                          ),
                                        ),
                                        if (doc.experienceYears > 0)
                                          Text(
                                            '${doc.experienceYears}+ Yrs exp',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                          ),
                                      ],
                                    ),
                                    if (doc.clinicName.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.local_hospital_outlined, size: 13, color: AppTheme.textMuted),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              doc.clinicName,
                                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
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
                      ),
                    );
                  },
                ),
        ),

        // Bottom Continue button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedDoctor == null
                  ? null
                  : () {
                      setState(() => _currentStep = 2);
                      _loadDoctorAvailability();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Next: Select Date & Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // STEP 2: SELECT DATE & TIME SLOT
  // ==========================================
  Widget _buildStep2SelectDateAndSlot() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Doctor summary banner
          if (_selectedDoctor != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x14012A58),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x40012A58)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                    child: Text(
                      _selectedDoctor!.name.isNotEmpty
                          ? _selectedDoctor!.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim()[0].toUpperCase()
                          : 'D',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedDoctor!.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF012A58)),
                        ),
                        Text(
                          '${_selectedDoctor!.specialty} • ${_selectedDoctor!.clinicName.isNotEmpty ? _selectedDoctor!.clinicName : "GS HEALTH Clinic"}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF012A58)),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 1),
                    child: const Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Consultation Mode Selector (In-Person vs Online)
          const Text(
            'Consultation Type',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const Key('booking_mode_in_person'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _selectedConsultationMode = 'In-Person';
                      _selectedTimeSlot = null;
                    });
                    _loadDoctorAvailability();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                    decoration: BoxDecoration(
                      color: _selectedConsultationMode == 'In-Person'
                          ? AppTheme.primaryBlue
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedConsultationMode == 'In-Person'
                            ? AppTheme.primaryBlue
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.local_hospital_outlined,
                          size: 16,
                          color: _selectedConsultationMode == 'In-Person' ? Colors.white : AppTheme.primaryBlue,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'In-Person',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _selectedConsultationMode == 'In-Person' ? Colors.white : AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  key: const Key('booking_mode_online'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _selectedConsultationMode = 'Online';
                      _selectedTimeSlot = null;
                    });
                    _loadDoctorAvailability();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                    decoration: BoxDecoration(
                      color: _selectedConsultationMode == 'Online'
                          ? AppTheme.primaryBlue
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedConsultationMode == 'Online'
                            ? AppTheme.primaryBlue
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.videocam_outlined,
                          size: 16,
                          color: _selectedConsultationMode == 'Online' ? Colors.white : AppTheme.primaryBlue,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Online Consultation',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _selectedConsultationMode == 'Online' ? Colors.white : AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            key: const Key('booking_hybrid_duration_hint'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 14, color: AppTheme.gsNavy),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    () {
                      final avail = _doctorAvailability;
                      final modeMatches = avail != null &&
                          avail.consultationType.toLowerCase() == _selectedConsultationMode.toLowerCase();
                      final dur = modeMatches
                          ? avail.consultationDurationMinutes
                          : BookingRulesConfig.durationForMode(_selectedConsultationMode);
                      final buf = modeMatches
                          ? avail.bufferMinutes
                          : BookingRulesConfig.bufferForMode(_selectedConsultationMode);
                      final hoursPart = (modeMatches && avail.startTime.isNotEmpty && avail.endTime.isNotEmpty)
                          ? ' • Hours: ${avail.startTime}–${avail.endTime}'
                          : '';
                      return '$_selectedConsultationMode duration: $dur mins (+${buf}m buffer)$hoursPart';
                    }(),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (!_doctorSupportsConsultationMode(_selectedDoctor, _selectedConsultationMode)) ...[
            const SizedBox(height: 8),
            Container(
              key: const Key('booking_unsupported_mode_warning'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _unsupportedModeErrorMessage(_selectedConsultationMode),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Date Selection Section
          const Text('1. Select Appointment Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
          const SizedBox(height: 8),

          // Horizontal Date Selector (Today + Next 14 Days)
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 15,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final nowRef = BookingRulesConfig.debugNowOverride ?? DateTime.now();
                final baseDay = DateTime(nowRef.year, nowRef.month, nowRef.day);
                final date = baseDay.add(Duration(days: idx));
                final dKey = _formatDateIsoLocal(date);
                final isDateBlocked = _configuredDateMap[dKey]?.isBlocked == true;
                final isSelected = date.year == _selectedDate.year &&
                    date.month == _selectedDate.month &&
                    date.day == _selectedDate.day;
                const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                      _selectedTimeSlot = null; // reset slot on date change
                    });
                    _loadDoctorAvailability();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 58,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDateBlocked ? const Color(0xFFFE3434) : AppTheme.primaryBlue)
                          : (isDateBlocked ? const Color(0x14FE3434) : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? (isDateBlocked ? const Color(0xFFFE3434) : AppTheme.primaryBlue)
                            : (isDateBlocked ? const Color(0x40FE3434) : const Color(0xFFE2E8F0)),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          weekdays[date.weekday - 1],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.9)
                                : (isDateBlocked ? const Color(0xFFFE3434) : AppTheme.textMuted),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          date.day.toString().padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : (isDateBlocked ? const Color(0xFFFE3434) : AppTheme.textDark),
                          ),
                        ),
                        if (isDateBlocked)
                          Text(
                            'Blocked',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : const Color(0xFFFE3434),
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
          const SizedBox(height: 6),
          Text(
            'Selected Date: ${_formatDate(_selectedDate)}',
            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 20),

          // Time Slot Selection Section
          Row(
            children: [
              const Expanded(
                child: Text(
                  '2. Select Available Time Slot',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const Key('booking_refresh_slots_btn'),
                tooltip: 'Refresh live slots',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.primaryBlue),
                onPressed: _isLoadingSlots ? null : () => _loadDoctorAvailability(silent: true),
              ),
            ],
          ),
          if (_slotRefreshNotice != null) ...[
            const SizedBox(height: 6),
            Container(
              key: const Key('booking_slot_unavailable_notice'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFC2410C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _slotRefreshNotice!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9A3412)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),

          if (_isLoadingSlots)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(height: 8),
                    Text('Fetching published doctor availability...', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  ],
                ),
              ),
            )
          else if (_doctorAvailability != null && _doctorAvailability!.isBlocked)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x14FE3434),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x40FE3434)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.block_rounded, color: Color(0xFFFE3434), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Doctor is unavailable on this date (${_doctorAvailability!.blockedReason ?? "Doctor on Leave / Clinic Closed"}). Please choose another date.',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFE3434)),
                    ),
                  ),
                ],
              ),
            )
          else if (BookingRulesConfig.filterBookableSlotsForDate(
                _selectedDate,
                _doctorAvailability?.allSlots ?? const <String>[],
              ).isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_busy_rounded, color: AppTheme.textMuted, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No bookable slots remaining for this date (minimum ${BookingRulesConfig.minAdvanceBookingMinutes}-minute advance booking applies). Please select another date.',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: () {
                final avail = _doctorAvailability!;
                final releasedTimes = avail.releasedSlots
                    .map((r) => (r['startTime'] ?? r['start_time'] ?? '').toString().trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                final regularBookable = BookingRulesConfig.filterBookableSlotsForDate(
                  _selectedDate,
                  avail.allSlots,
                );
                final displaySlots = <String>[...regularBookable];
                for (final rt in releasedTimes) {
                  if (!displaySlots.any((s) => s.trim().toLowerCase() == rt.toLowerCase())) {
                    displaySlots.insert(0, rt);
                  }
                }
                return displaySlots.map((slot) {
                  final releasedId = _findReleasedSlotIdForTime(slot);
                  final isReleased = releasedId != null;
                  final isLockedByOther = avail.lockedSlots.any((l) => l.trim().toLowerCase() == slot.trim().toLowerCase());
                  final isBooked = isLockedByOther ||
                      avail.bookedSlots.any((b) => b.trim().toLowerCase() == slot.trim().toLowerCase()) ||
                      (!isReleased && _isSlotBooked(slot));
                  final isSelected = _selectedTimeSlot == slot;

                  return SizedBox(
                    width: 142,
                    child: InkWell(
                      key: isReleased ? Key('released_slot_chip_${slot.replaceAll(' ', '_')}') : null,
                      onTap: isBooked
                          ? null
                          : () => setState(() {
                                _selectedTimeSlot = slot;
                                _selectedReleasedSlotId = releasedId;
                              }),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isBooked
                              ? const Color(0xFFF1F5F9)
                              : isSelected
                                  ? AppTheme.primaryBlue
                                  : (isReleased ? const Color(0xFFECFDF5) : Colors.white),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isBooked
                                ? const Color(0xFFE2E8F0)
                                : isSelected
                                    ? AppTheme.primaryBlue
                                    : (isReleased ? const Color(0xFF10B981) : const Color(0xFFCBD5E1)),
                            width: isReleased && !isBooked ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isBooked
                                  ? Icons.block_rounded
                                  : isSelected
                                      ? Icons.check_circle_rounded
                                      : (isReleased ? Icons.bolt_rounded : Icons.access_time_rounded),
                              size: 14,
                              color: isBooked
                                  ? const Color(0xFF94A3B8)
                                  : isSelected
                                      ? Colors.white
                                      : (isReleased ? const Color(0xFF059669) : AppTheme.primaryBlue),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                isReleased && !isBooked ? '$slot • Early' : slot,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: isBooked
                                      ? const Color(0xFF94A3B8)
                                      : isSelected
                                          ? Colors.white
                                          : (isReleased ? const Color(0xFF065F46) : AppTheme.textDark),
                                  decoration: isBooked ? TextDecoration.lineThrough : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList();
              }(),
            ),
          const SizedBox(height: 18),

          // Next button (Acquires temporary slot lock before proceeding!)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('booking_next_to_reason_btn'),
              onPressed: (_selectedTimeSlot == null || (_doctorAvailability?.isBlocked ?? false) || _isAcquiringLock)
                  ? null
                  : _acquireLockAndProceedToStep3,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _isAcquiringLock ? 'Reserving Slot...' : 'Next: Reason for Visit',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Earlier-Slot Notification Opt-In Preference Card
          Container(
            key: const Key('booking_earlier_slot_pref_card'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_outlined, size: 18, color: AppTheme.primaryBlue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notify me if an earlier slot opens',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Get instant alerts when the doctor finishes early',
                        style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const Key('booking_notify_earlier_slots_switch'),
                  value: _notifyEarlierSlots,
                  activeColor: AppTheme.primaryBlue,
                  onChanged: _isSavingNotifPref ? null : _toggleEarlierSlotNotification,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // STEP 3: REASON & SYMPTOMS
  // ==========================================
  Widget _buildStep3ReasonAndSymptoms() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Consultation Reason / Symptoms', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
          const SizedBox(height: 8),

          DropdownButtonFormField<String>(
            key: ValueKey('booking_category_${_activeClinicalProfile.code}'),
            initialValue: _categories.contains(_selectedCategory) ? _selectedCategory : _categories.first,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
            ),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (val) => setState(() => _selectedCategory = val ?? _selectedCategory),
          ),
          const SizedBox(height: 16),

          const Text('Describe Symptoms / Notes (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
          const SizedBox(height: 8),

          TextField(
            controller: _symptomsController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: _activeClinicalProfile.symptomHint,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
            ),
          ),
          const SizedBox(height: 16),

          const Text('Pain Severity Level:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
          const SizedBox(height: 8),

          Row(
            children: ['Mild', 'Moderate', 'Severe'].map((sev) {
              final isSelected = _selectedSeverity == sev;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => setState(() => _selectedSeverity = sev),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (sev == 'Severe' ? const Color(0x14FE3434) : sev == 'Moderate' ? const Color(0x14FE3434) : const Color(0x14012A58))
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? (sev == 'Severe' ? const Color(0xFFFE3434) : sev == 'Moderate' ? const Color(0xFFFE3434) : const Color(0xFFFE3434))
                              : const Color(0xFFCBD5E1),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          sev,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            color: isSelected
                                ? (sev == 'Severe' ? const Color(0xFFFE3434) : sev == 'Moderate' ? const Color(0xFFFE3434) : const Color(0xFF012A58))
                                : AppTheme.textDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _currentStep = 4),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Next: Review Booking Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // STEP 4: REVIEW & CONFIRM
  // ==========================================
  Widget _buildStep4ReviewAndConfirm() {
    final patient = _patientService.currentPatient;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Review Appointment Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
          const SizedBox(height: 12),

          if (_activeSlotLock != null && _lockSecondsRemaining > 0) ...[
            Container(
              key: const Key('booking_slot_lock_banner'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock_rounded, size: 16, color: Color(0xFF047857)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Slot reserved for ${_formatCountdown(_lockSecondsRemaining)} — confirm before timer expires',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF065F46)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x14FE3434),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x40FE3434)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFFE3434), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFFE3434)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Detailed Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildSummaryRow(
                  icon: Icons.person_rounded,
                  label: 'Doctor',
                  value: _selectedDoctor?.name ?? 'Attending Specialist',
                  subValue: _selectedDoctor?.specialty,
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildSummaryRow(
                  icon: _selectedConsultationMode == 'Online'
                      ? Icons.videocam_rounded
                      : Icons.local_hospital_rounded,
                  label: 'Consultation Mode',
                  value: _selectedConsultationMode == 'Online'
                      ? 'Online Consultation'
                      : 'In-Person Consultation',
                  subValue: _selectedDoctor?.clinicName.isNotEmpty == true
                      ? _selectedDoctor!.clinicName
                      : 'Verified Healthcare Practice',
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildSummaryRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'Date & Time',
                  value: _formatDate(_selectedDate),
                  subValue: _selectedTimeSlot ?? '',
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildSummaryRow(
                  icon: Icons.medical_services_rounded,
                  label: 'Reason for Visit',
                  value: _selectedCategory,
                  subValue: _symptomsController.text.trim().isNotEmpty
                      ? _symptomsController.text.trim()
                      : 'Severity: $_selectedSeverity',
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildSummaryRow(
                  icon: Icons.account_circle_rounded,
                  label: 'Patient',
                  value: patient.name.isNotEmpty ? patient.name : 'Registered Patient',
                  subValue: patient.phone.isNotEmpty ? patient.phone : null,
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildSummaryRow(
                  icon: Icons.payments_rounded,
                  label: 'Consultation Fee',
                  value: BookingRulesConfig.formatRealFee(_selectedDoctor?.consultationFee),
                  subValue: _selectedConsultationMode == 'Online'
                      ? 'Online consultation fee'
                      : 'Pay at clinic during visit',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitBooking,
              icon: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                _isSubmitting ? 'Confirming Booking...' : 'Confirm & Book Appointment',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
    String? subValue,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primaryBlue, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              const SizedBox(height: 1),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
              if (subValue != null && subValue.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(subValue, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // STEP 5: SUCCESS CONFIRMATION
  // ==========================================
  Widget _buildStep5Success() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0x14012A58),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x40012A58), width: 2),
              ),
              child: const Icon(Icons.check_rounded, color: Color(0xFF012A58), size: 48),
            ),
            const SizedBox(height: 18),
            const Text(
              'Visit Booked Successfully!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: AppTheme.textDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your appointment with ${_selectedDoctor?.name ?? "your doctor"} is scheduled for ${_formatDate(_selectedDate)} at ${_selectedTimeSlot ?? ""}.',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
              textAlign: TextAlign.center,
            ),
            if (_selectedConsultationMode == 'Online') ...[
              const SizedBox(height: 14),
              Container(
                key: const Key('booking_confirmed_online_access_badge'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF7DD3FC)),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_rounded, size: 18, color: Color(0xFF0284C7)),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'In-App Video Consultation Enabled',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0369A1),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'You can join the live video & chat consultation room directly from My Visits at your scheduled slot.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF0C4A6E), height: 1.3),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key('booking_confirmed_open_online_consultation_btn'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onBookingSuccess?.call();
                        },
                        icon: const Icon(Icons.video_call_rounded, size: 17),
                        label: const Text(
                          'Access Video Consultation Room',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0284C7),
                          side: const BorderSide(color: Color(0xFF0284C7), width: 1.3),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onBookingSuccess?.call();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('View in My Appointments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Submission handler (Atomic confirmation using active slot lock + releasedSlotId)
  Future<void> _submitBooking() async {
    if (_selectedDoctor == null || _selectedTimeSlot == null) return;
    if (!_doctorSupportsConsultationMode(_selectedDoctor, _selectedConsultationMode)) {
      setState(() {
        _errorMessage = _unsupportedModeErrorMessage(_selectedConsultationMode);
      });
      return;
    }
    if (_activeSlotLock != null && _activeSlotLock!.isExpired) {
      await _releaseActiveLock();
      if (!mounted) return;
      setState(() {
        _currentStep = 2;
        _selectedTimeSlot = null;
        _selectedReleasedSlotId = null;
        _slotRefreshNotice = 'Your temporary slot reservation expired. Please select a time slot again.';
      });
      unawaited(_loadDoctorAvailability(silent: true));
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;
    final dateStr = _selectedDate.toIso8601String();
    final lockId = _activeSlotLock?.lockId;
    final releasedId = _selectedReleasedSlotId;

    try {
      final res = await _patientService.bookAppointment(
        dentistId: docId,
        clinicId: '',
        date: dateStr,
        timeSlot: _selectedTimeSlot!,
        treatment: _selectedCategory,
        consultationMode: _selectedConsultationMode,
        symptoms: _symptomsController.text.trim(),
        lockId: lockId,
        releasedSlotId: releasedId,
        requireLock: lockId != null || releasedId != null,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        _lockCountdownTimer?.cancel();
        _activeSlotLock = null;
        _lockSecondsRemaining = 0;
        setState(() {
          _isSubmitting = false;
          _currentStep = 5; // Move to Success Step
        });
      } else {
        final reason = (res['reason'] ?? '').toString().toUpperCase();
        final isLockOrSlotGone = reason == 'LOCK_REQUIRED' ||
            reason == 'LOCK_MISMATCH_OR_EXPIRED' ||
            reason == 'RELEASED_SLOT_UNAVAILABLE' ||
            reason == 'RELEASED_SLOT_LOCK_MISMATCH' ||
            reason == 'SLOT_LOCKED' ||
            res['conflict'] == true;
        if (isLockOrSlotGone) {
          await _releaseActiveLock();
          if (!mounted) return;
          setState(() {
            _isSubmitting = false;
            _currentStep = 2;
            _selectedTimeSlot = null;
            _selectedReleasedSlotId = null;
            _slotRefreshNotice = res['message']?.toString() ??
                'This slot is no longer available. Please select another time.';
          });
          unawaited(_loadDoctorAvailability(silent: true));
        } else {
          setState(() {
            _isSubmitting = false;
            _errorMessage = res['message']?.toString() ?? 'Unable to confirm booking. Please try another time slot.';
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Booking failed: $e';
      });
    }
  }
}

