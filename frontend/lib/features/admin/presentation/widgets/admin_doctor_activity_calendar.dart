import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';

/// GS Health Admin — Complete Doctor Activity Calendar
///
/// Features:
/// - Google Calendar–style Monthly Calendar (Sun–Sat, Today highlight, Prev/Next Month, Month/Year picker, Today jump)
/// - Activity color indicators & count badges (Appointments, Completed, Pending, Referrals) + Legend
/// - Daily Activity Summary Cards (7 real-time KPI metrics from backend records)
/// - Doctor-wise Activity Table (9 columns + click any doctor for daily detail drill-down)
/// - Patient & Appointment Details (paginated, view dialog, referral info, status/doctor filters)
/// - Referral Tracking (paginated, Pending / Accepted / Completed / Rejected status filters)
/// - Search by doctor name or patient name, responsive desktop/tablet/mobile layouts, loading/empty/error states
class AdminDoctorActivityCalendarSection extends StatefulWidget {
  final PatientProblemService problemService;
  final DateTime? initialDate;

  const AdminDoctorActivityCalendarSection({
    super.key,
    required this.problemService,
    this.initialDate,
  });

  @override
  State<AdminDoctorActivityCalendarSection> createState() =>
      _AdminDoctorActivityCalendarSectionState();
}

class _AdminDoctorActivityCalendarSectionState
    extends State<AdminDoctorActivityCalendarSection> {
  static const List<String> _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const List<String> _appointmentStatusOptions = [
    'All',
    'Pending',
    'Completed',
    'Cancelled',
  ];
  static const List<String> _referralStatusOptions = [
    'All',
    'Pending',
    'Accepted',
    'Completed',
    'Rejected',
  ];

  // Activity Indicator Palette
  static const Color _colAppointments = Color(0xFF2563EB); // Blue
  static const Color _colCompleted = Color(0xFF059669); // Emerald Green
  static const Color _colPending = Color(0xFFD97706); // Amber
  static const Color _colReferrals = Color(0xFF7C3AED); // Purple
  static const Color _colCancelled = Color(0xFFDC2626); // Red

  late DateTime _selectedDate;
  late DateTime _displayedMonth;

  String _selectedDoctorId = 'All';
  String _selectedAppointmentStatus = 'All';
  String _selectedReferralStatus = 'All';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  int _currentPage = 1;
  static const int _pageSize = 20;

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _calendarData;

  @override
  void initState() {
    super.initState();
    final now = widget.initialDate ?? DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _displayedMonth = DateTime(now.year, now.month, 1);
    _loadCalendarData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _formatYmd(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  String _formatYm(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    return '${d.year}-$m';
  }

  String _formatReadableDate(DateTime d) {
    return '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _loadCalendarData({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final res = await ApiService().fetchAdminDoctorActivityCalendar(
      date: _formatYmd(_selectedDate),
      month: _formatYm(_displayedMonth),
      doctorId: _selectedDoctorId == 'All' ? null : _selectedDoctorId,
      appointmentStatus:
          _selectedAppointmentStatus == 'All' ? null : _selectedAppointmentStatus,
      referralStatus:
          _selectedReferralStatus == 'All' ? null : _selectedReferralStatus,
      search: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
      page: _currentPage,
      pageSize: _pageSize,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      setState(() {
        _calendarData = res;
        _isLoading = false;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = (res['message'] ?? 'Failed to load Doctor Activity Calendar.').toString();
      });
    }
  }

  void _selectDate(DateTime date) {
    final clean = DateTime(date.year, date.month, date.day);
    setState(() {
      _selectedDate = clean;
      _displayedMonth = DateTime(clean.year, clean.month, 1);
      _currentPage = 1;
    });
    _loadCalendarData();
  }

  void _goToPreviousMonth() {
    final prev = DateTime(_displayedMonth.year, _displayedMonth.month - 1, 1);
    setState(() {
      _displayedMonth = prev;
      _selectedDate = prev;
      _currentPage = 1;
    });
    _loadCalendarData();
  }

  void _goToNextMonth() {
    final next = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
    setState(() {
      _displayedMonth = next;
      _selectedDate = next;
      _currentPage = 1;
    });
    _loadCalendarData();
  }

  void _goToToday() {
    final now = widget.initialDate ?? DateTime.now();
    _selectDate(now);
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _currentPage = 1);
      _loadCalendarData();
    });
  }

  void _clearAllFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _selectedDoctorId = 'All';
      _selectedAppointmentStatus = 'All';
      _selectedReferralStatus = 'All';
      _currentPage = 1;
    });
    _loadCalendarData();
  }

  bool get _hasActiveFilters =>
      _selectedDoctorId != 'All' ||
      _selectedAppointmentStatus != 'All' ||
      _selectedReferralStatus != 'All' ||
      _searchController.text.trim().isNotEmpty;

  Future<void> _showMonthYearPickerDialog() async {
    int tempYear = _displayedMonth.year;
    int tempMonth = _displayedMonth.month;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Row(
              children: [
                Icon(Icons.calendar_month_rounded, color: AppTheme.gsNavy, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Select Month & Year',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          tooltip: 'Previous Year',
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: () => setModalState(() => tempYear -= 1),
                        ),
                        Text(
                          '$tempYear',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.gsNavy,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next Year',
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: () => setModalState(() => tempYear += 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(12, (idx) {
                        final m = idx + 1;
                        final selected = m == tempMonth;
                        return InkWell(
                          onTap: () => setModalState(() => tempMonth = m),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 96,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? AppTheme.gsNavy : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _monthNames[idx].substring(0, 3),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: selected ? Colors.white : AppTheme.textDark,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gsNavy,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    _selectDate(DateTime(tempYear, tempMonth, 1));
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> get _monthlyCalendar =>
      Map<String, dynamic>.from((_calendarData?['monthlyCalendar'] as Map?) ?? const {});

  Map<String, dynamic> get _dailySummary =>
      Map<String, dynamic>.from((_calendarData?['dailySummary'] as Map?) ?? const {});

  List<Map<String, dynamic>> get _doctorActivity =>
      ((_calendarData?['doctorActivity'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _appointments =>
      ((_calendarData?['appointments'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _referrals =>
      ((_calendarData?['referrals'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _availableDoctors =>
      ((_calendarData?['availableDoctors'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  Map<String, dynamic> get _appointmentsPagination =>
      Map<String, dynamic>.from((_calendarData?['appointmentsPagination'] as Map?) ?? const {});

  Map<String, dynamic> get _referralsPagination =>
      Map<String, dynamic>.from((_calendarData?['referralsPagination'] as Map?) ?? const {});

  int _intVal(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width < 680;
        final isTablet = width >= 680 && width < 1060;

        return RefreshIndicator(
          onRefresh: () => _loadCalendarData(showSpinner: false),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(isMobile ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPageHeader(isMobile),
                const SizedBox(height: 14),
                _buildFilterToolbar(isMobile),
                const SizedBox(height: 16),
                if (_errorMessage != null && _calendarData == null)
                  _buildErrorCard()
                else ...[
                  if (_errorMessage != null) ...[
                    _buildInlineWarningBanner(_errorMessage!),
                    const SizedBox(height: 12),
                  ],
                  _buildMonthlyCalendarCard(isMobile, isTablet),
                  const SizedBox(height: 18),
                  if (_isLoading && _calendarData == null)
                    _buildLoadingCard()
                  else ...[
                    _buildDailySummarySection(isMobile, isTablet),
                    const SizedBox(height: 18),
                    _buildDoctorActivitySection(isMobile),
                    const SizedBox(height: 18),
                    _buildAppointmentsSection(isMobile),
                    const SizedBox(height: 18),
                    _buildReferralsSection(isMobile),
                  ],
                ],
                const SizedBox(height: 28),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.gsNavy, Color(0xFF0A4380)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.gsNavy.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Doctor Activity Calendar',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Monthly doctor schedules, consultations, patient visits & referral tracking (${_calendarData?['timezone'] ?? 'Asia/Kolkata'})',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('doctor_calendar_refresh_btn'),
            tooltip: 'Refresh Calendar',
            onPressed: _isLoading ? null : () => _loadCalendarData(),
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterToolbar(bool isMobile) {
    final doctorItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'All', child: Text('All Doctors', overflow: TextOverflow.ellipsis)),
      ..._availableDoctors.map((d) {
        final id = (d['doctorId'] ?? '').toString();
        final name = (d['doctorName'] ?? 'Doctor').toString();
        return DropdownMenuItem(
          value: id,
          child: Text(name, overflow: TextOverflow.ellipsis),
        );
      }),
    ];

    final effectiveDoctorValue = doctorItems.any((i) => i.value == _selectedDoctorId)
        ? _selectedDoctorId
        : 'All';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: isMobile ? double.infinity : 250,
            child: TextField(
              key: const Key('doctor_calendar_search_field'),
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search doctor or patient...',
                hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.textMuted),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _currentPage = 1);
                          _loadCalendarData();
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
            ),
          ),
          SizedBox(
            width: isMobile ? double.infinity : 200,
            child: DropdownButtonFormField<String>(
              key: const Key('doctor_calendar_doctor_filter'),
              initialValue: effectiveDoctorValue,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Doctor',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: doctorItems,
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _selectedDoctorId = val;
                  _currentPage = 1;
                });
                _loadCalendarData();
              },
            ),
          ),
          SizedBox(
            width: isMobile ? 165 : 175,
            child: DropdownButtonFormField<String>(
              key: const Key('doctor_calendar_appt_status_filter'),
              initialValue: _selectedAppointmentStatus,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Appointment Status',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: _appointmentStatusOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _selectedAppointmentStatus = val;
                  _currentPage = 1;
                });
                _loadCalendarData();
              },
            ),
          ),
          SizedBox(
            width: isMobile ? 165 : 175,
            child: DropdownButtonFormField<String>(
              key: const Key('doctor_calendar_ref_status_filter'),
              initialValue: _selectedReferralStatus,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Referral Status',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: _referralStatusOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _selectedReferralStatus = val;
                  _currentPage = 1;
                });
                _loadCalendarData();
              },
            ),
          ),
          if (_hasActiveFilters)
            TextButton.icon(
              key: const Key('doctor_calendar_clear_filters_btn'),
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
              label: const Text('Clear Filters'),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthlyCalendarCard(bool isMobile, bool isTablet) {
    final firstDayOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    // DateTime.weekday: Mon=1 .. Sat=6, Sun=7. For Sunday-first grid, Sunday offset = 0.
    final leadingDays = firstDayOfMonth.weekday % 7;
    final daysInMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    final totalCells = ((leadingDays + daysInMonth + 6) ~/ 7) * 7;

    final todayRef = widget.initialDate ?? DateTime.now();
    final todayYmd = (_calendarData?['today']?.toString().trim().isNotEmpty == true)
        ? _calendarData!['today'].toString().trim()
        : _formatYmd(todayRef);
    final selectedYmd = _formatYmd(_selectedDate);
    final monthlyMap = _monthlyCalendar;

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Calendar Top Navigation Bar
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 4,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(
                    key: const Key('doctor_calendar_today_btn'),
                    onPressed: _goToToday,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.gsNavy,
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Today', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    key: const Key('doctor_calendar_prev_month_btn'),
                    tooltip: 'Previous Month',
                    visualDensity: VisualDensity.compact,
                    onPressed: _goToPreviousMonth,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  IconButton(
                    key: const Key('doctor_calendar_next_month_btn'),
                    tooltip: 'Next Month',
                    visualDensity: VisualDensity.compact,
                    onPressed: _goToNextMonth,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  InkWell(
                    key: const Key('doctor_calendar_month_year_btn'),
                    onTap: _showMonthYearPickerDialog,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_monthNames[_displayedMonth.month - 1]} ${_displayedMonth.year}',
                            style: TextStyle(
                              fontSize: isMobile ? 15.5 : 20,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.textMedium),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Legend Strip
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _buildLegendChip('Appointments', _colAppointments),
                  _buildLegendChip('Completed', _colCompleted),
                  _buildLegendChip('Pending', _colPending),
                  _buildLegendChip('Referrals', _colReferrals),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Weekday Headers (Sun - Sat)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: _weekdays
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: (day == 'Sun' || day == 'Sat')
                                ? AppTheme.gsNavy
                                : AppTheme.textMedium,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Monthly Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalCells,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: isMobile ? 4 : 6,
              mainAxisSpacing: isMobile ? 4 : 6,
              mainAxisExtent: isMobile ? 64 : (isTablet ? 108 : 104),
            ),
            itemBuilder: (context, index) {
              final dayOffset = index - leadingDays;
              final cellDate = DateTime(_displayedMonth.year, _displayedMonth.month, 1 + dayOffset);
              final isCurrentMonth = cellDate.month == _displayedMonth.month &&
                  cellDate.year == _displayedMonth.year;
              final ymd = _formatYmd(cellDate);
              final isToday = ymd == todayYmd;
              final isSelected = ymd == selectedYmd;

              final rawBucket = monthlyMap[ymd];
              final bucket = rawBucket is Map ? Map<String, dynamic>.from(rawBucket) : const <String, dynamic>{};
              final totalAppts = _intVal(bucket, 'totalAppointments');
              final completed = _intVal(bucket, 'completedAppointments');
              final pending = _intVal(bucket, 'pendingAppointments');
              final referrals = _intVal(bucket, 'totalReferrals');
              final hasAnyActivity = totalAppts > 0 || referrals > 0;

              return InkWell(
                key: Key('doctor_calendar_cell_$ymd'),
                onTap: () => _selectDate(cellDate),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: EdgeInsets.all(isMobile ? 4 : 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.gsNavy.withValues(alpha: 0.08)
                        : (isCurrentMonth ? Colors.white : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.gsNavy
                          : (isToday
                              ? _colAppointments
                              : const Color(0xFFE2E8F0)),
                      width: isSelected ? 2 : (isToday ? 1.5 : 1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: isMobile ? 22 : 26,
                            height: isMobile ? 22 : 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isToday
                                  ? AppTheme.gsNavy
                                  : (isSelected
                                      ? AppTheme.gsNavy.withValues(alpha: 0.14)
                                      : Colors.transparent),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${cellDate.day}',
                              style: TextStyle(
                                fontSize: isMobile ? 11 : 12.5,
                                fontWeight: (isToday || isSelected)
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isToday
                                    ? Colors.white
                                    : (isCurrentMonth
                                        ? AppTheme.textDark
                                        : AppTheme.textMuted.withValues(alpha: 0.55)),
                              ),
                            ),
                          ),
                          if (!isMobile && totalAppts > 0) ...[
                            const Spacer(),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: _colAppointments.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$totalAppts',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: _colAppointments,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (hasAnyActivity)
                        Flexible(
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: isMobile
                                ? Wrap(
                                    spacing: 3,
                                    runSpacing: 2,
                                    children: [
                                      if (totalAppts > 0) _buildMiniDot(_colAppointments),
                                      if (completed > 0) _buildMiniDot(_colCompleted),
                                      if (pending > 0) _buildMiniDot(_colPending),
                                      if (referrals > 0) _buildMiniDot(_colReferrals),
                                    ],
                                  )
                                : Wrap(
                                    spacing: 4,
                                    runSpacing: 3,
                                    children: [
                                      if (completed > 0)
                                        _buildCellCountBadge('C:$completed', _colCompleted),
                                      if (pending > 0)
                                        _buildCellCountBadge('P:$pending', _colPending),
                                      if (referrals > 0)
                                        _buildCellCountBadge('R:$referrals', _colReferrals),
                                    ],
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLegendChip(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
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

  Widget _buildMiniDot(Color color) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildCellCountBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildDailySummarySection(bool isMobile, bool isTablet) {
    final s = _dailySummary;
    final cards = [
      (
        key: 'summary_doctors_active',
        label: 'Total Doctors Active',
        value: _intVal(s, 'totalDoctorsActive'),
        icon: Icons.medical_services_rounded,
        color: AppTheme.gsNavy,
      ),
      (
        key: 'summary_total_appointments',
        label: 'Total Appointments',
        value: _intVal(s, 'totalAppointments'),
        icon: Icons.event_note_rounded,
        color: _colAppointments,
      ),
      (
        key: 'summary_patients_checked',
        label: 'Total Patients Checked',
        value: _intVal(s, 'totalPatientsChecked'),
        icon: Icons.how_to_reg_rounded,
        color: const Color(0xFF0D9488),
      ),
      (
        key: 'summary_total_referrals',
        label: 'Total Referrals',
        value: _intVal(s, 'totalReferrals'),
        icon: Icons.group_add_rounded,
        color: _colReferrals,
      ),
      (
        key: 'summary_pending_appointments',
        label: 'Pending Appointments',
        value: _intVal(s, 'pendingAppointments'),
        icon: Icons.schedule_rounded,
        color: _colPending,
      ),
      (
        key: 'summary_completed_appointments',
        label: 'Completed Appointments',
        value: _intVal(s, 'completedAppointments'),
        icon: Icons.check_circle_rounded,
        color: _colCompleted,
      ),
      (
        key: 'summary_cancelled_appointments',
        label: 'Cancelled Appointments',
        value: _intVal(s, 'cancelledAppointments'),
        icon: Icons.cancel_rounded,
        color: _colCancelled,
      ),
    ];

    final crossAxisCount = isMobile ? 2 : (isTablet ? 3 : 4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.insights_rounded, color: AppTheme.gsNavy, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Daily Activity Summary — ${_formatReadableDate(_selectedDate)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: isMobile ? 96 : 102,
          ),
          itemBuilder: (context, idx) {
            final item = cards[idx];
            return Container(
              key: Key(item.key),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(item.icon, color: item.color, size: 17),
                      ),
                      const Spacer(),
                      Text(
                        '${item.value}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: item.color,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMedium,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDoctorActivitySection(bool isMobile) {
    final rows = _doctorActivity;

    return _buildSectionContainer(
      title: 'Doctor-wise Activity',
      subtitle: 'Click any doctor row to inspect detailed daily consultations and referrals',
      icon: Icons.medical_information_rounded,
      badgeCount: rows.length,
      child: rows.isEmpty
          ? _buildEmptyState(
              icon: Icons.person_off_outlined,
              title: 'No doctor activity recorded',
              subtitle:
                  'No doctors had appointments or referrals on ${_formatReadableDate(_selectedDate)}.',
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const Key('doctor_calendar_doctor_table'),
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                columnSpacing: 20,
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Doctor Name', style: TextStyle(fontWeight: FontWeight.w700))),
                  DataColumn(label: Text('Doctor ID', style: TextStyle(fontWeight: FontWeight.w700))),
                  DataColumn(numeric: true, label: Text('Total Appointments', style: TextStyle(fontWeight: FontWeight.w700))),
                  DataColumn(numeric: true, label: Text('Patients Checked', style: TextStyle(fontWeight: FontWeight.w700))),
                  DataColumn(numeric: true, label: Text('Referrals Received', style: TextStyle(fontWeight: FontWeight.w700))),
                  DataColumn(numeric: true, label: Text('Referrals Given', style: TextStyle(fontWeight: FontWeight.w700))),
                  DataColumn(numeric: true, label: Text('Pending Appointments', style: TextStyle(fontWeight: FontWeight.w700))),
                  DataColumn(numeric: true, label: Text('Completed Appointments', style: TextStyle(fontWeight: FontWeight.w700))),
                  DataColumn(numeric: true, label: Text('Cancelled Appointments', style: TextStyle(fontWeight: FontWeight.w700))),
                ],
                rows: rows.map((doc) {
                  final docId = (doc['doctorId'] ?? '').toString();
                  final docName = (doc['doctorName'] ?? 'Doctor').toString();
                  final shortId = docId.length > 12 ? '${docId.substring(0, 12)}…' : docId;
                  return DataRow(
                    onSelectChanged: (_) => _showDoctorDailyDetailDialog(doc),
                    cells: [
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_rounded, size: 16, color: AppTheme.gsNavy),
                            const SizedBox(width: 6),
                            Text(
                              docName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.gsNavy,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(Text(shortId, style: const TextStyle(fontSize: 12, color: AppTheme.textMedium))),
                      DataCell(Text('${_intVal(doc, 'totalAppointments')}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(Text('${_intVal(doc, 'patientsChecked')}')),
                      DataCell(Text('${_intVal(doc, 'referralsReceived')}', style: const TextStyle(color: _colReferrals, fontWeight: FontWeight.w600))),
                      DataCell(Text('${_intVal(doc, 'referralsGiven')}', style: const TextStyle(color: _colReferrals, fontWeight: FontWeight.w600))),
                      DataCell(Text('${_intVal(doc, 'pendingAppointments')}', style: const TextStyle(color: _colPending, fontWeight: FontWeight.w600))),
                      DataCell(Text('${_intVal(doc, 'completedAppointments')}', style: const TextStyle(color: _colCompleted, fontWeight: FontWeight.w600))),
                      DataCell(Text('${_intVal(doc, 'cancelledAppointments')}', style: const TextStyle(color: _colCancelled, fontWeight: FontWeight.w600))),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }

  void _showDoctorDailyDetailDialog(Map<String, dynamic> doc) {
    final docId = (doc['doctorId'] ?? '').toString();
    final docUserId = (doc['userId'] ?? '').toString();
    final docName = (doc['doctorName'] ?? 'Doctor').toString();
    final specialty = (doc['specialty'] ?? 'General Medicine').toString();

    final docAppts = _appointments.where((a) {
      final aDocId = (a['doctorId'] ?? '').toString();
      final aDocUid = (a['doctorUserId'] ?? '').toString();
      return (docId.isNotEmpty && aDocId == docId) ||
          (docUserId.isNotEmpty && (aDocUid == docUserId || aDocId == docUserId));
    }).toList();

    final docRefs = _referrals.where((r) {
      final targetId = (r['referredDoctorId'] ?? '').toString();
      final refDocId = (r['referringDoctorId'] ?? '').toString();
      return (docId.isNotEmpty && (targetId == docId || refDocId == docId)) ||
          (docUserId.isNotEmpty && (targetId == docUserId || refDocId == docUserId));
    }).toList();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppTheme.gsNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.medical_services_rounded, color: AppTheme.gsNavy, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            docName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$specialty • ID: $docId • ${_formatReadableDate(_selectedDate)}',
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildMiniStatPill('Appointments: ${_intVal(doc, 'totalAppointments')}', _colAppointments),
                    _buildMiniStatPill('Checked: ${_intVal(doc, 'patientsChecked')}', const Color(0xFF0D9488)),
                    _buildMiniStatPill('Pending: ${_intVal(doc, 'pendingAppointments')}', _colPending),
                    _buildMiniStatPill('Completed: ${_intVal(doc, 'completedAppointments')}', _colCompleted),
                    _buildMiniStatPill('Cancelled: ${_intVal(doc, 'cancelledAppointments')}', _colCancelled),
                    _buildMiniStatPill('Refs In: ${_intVal(doc, 'referralsReceived')}', _colReferrals),
                    _buildMiniStatPill('Refs Out: ${_intVal(doc, 'referralsGiven')}', _colReferrals),
                  ],
                ),
                const Divider(height: 22),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Consultations (${docAppts.length})',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (docAppts.isEmpty)
                          const Text(
                            'No appointments for this doctor on the selected page/date.',
                            style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                          )
                        else
                          ...docAppts.map((a) {
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.access_time_rounded, size: 18, color: AppTheme.gsNavy),
                              title: Text(
                                '${a['patientName'] ?? 'Patient'} (${a['patientId'] ?? 'N/A'})',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${a['appointmentTime'] ?? ''} • ${a['consultationType'] ?? 'In-Person'}',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              trailing: _buildStatusBadge((a['statusCategory'] ?? a['status'] ?? 'Pending').toString()),
                            );
                          }),
                        const SizedBox(height: 14),
                        Text(
                          'Referrals (${docRefs.length})',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (docRefs.isEmpty)
                          const Text(
                            'No referrals for this doctor on the selected date.',
                            style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                          )
                        else
                          ...docRefs.map((r) {
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.group_add_rounded, size: 18, color: _colReferrals),
                              title: Text(
                                '${r['patientName'] ?? 'Patient'} • Ref ${r['referralId'] ?? ''}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'From: ${r['referringDoctorName'] ?? 'N/A'} → To: ${r['referredDoctorName'] ?? 'N/A'}',
                                style: const TextStyle(fontSize: 11.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: _buildStatusBadge((r['referralStatus'] ?? 'Pending').toString()),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogCtx).pop();
                        if (docId.isNotEmpty) {
                          setState(() {
                            _selectedDoctorId = docId;
                            _currentPage = 1;
                          });
                          _loadCalendarData();
                        }
                      },
                      child: const Text('Filter Calendar by This Doctor'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gsNavy,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppointmentsSection(bool isMobile) {
    final appts = _appointments;
    final totalItems = _intVal(_appointmentsPagination, 'totalItems');
    final totalPages = _intVal(_appointmentsPagination, 'totalPages').clamp(1, 9999);
    final currentPage = _intVal(_appointmentsPagination, 'page').clamp(1, totalPages);

    return _buildSectionContainer(
      title: 'Patient & Appointment Details',
      subtitle: 'Appointments scheduled for ${_formatReadableDate(_selectedDate)}',
      icon: Icons.event_available_rounded,
      badgeCount: totalItems > 0 ? totalItems : appts.length,
      child: appts.isEmpty
          ? _buildEmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No appointments found',
              subtitle:
                  'There are no appointments matching the current filters on ${_formatReadableDate(_selectedDate)}.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isMobile)
                  Column(
                    children: appts.map(_buildMobileAppointmentCard).toList(),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      key: const Key('doctor_calendar_appointments_table'),
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                      columnSpacing: 18,
                      columns: const [
                        DataColumn(label: Text('Patient Name', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Patient ID', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Doctor Name', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Consultation Type', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Referral Info', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.w700))),
                      ],
                      rows: appts.map((a) {
                        final pId = (a['patientId'] ?? 'N/A').toString();
                        final shortPid = pId.length > 10 ? '${pId.substring(0, 10)}…' : pId;
                        final refInfo = a['referralInfo'] is Map
                            ? Map<String, dynamic>.from(a['referralInfo'] as Map)
                            : null;

                        return DataRow(
                          cells: [
                            DataCell(Text((a['patientName'] ?? 'Patient').toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text(shortPid, style: const TextStyle(fontSize: 12, color: AppTheme.textMedium))),
                            DataCell(Text((a['doctorName'] ?? 'Doctor').toString())),
                            DataCell(Text('${a['appointmentDate'] ?? ''} • ${a['appointmentTime'] ?? 'TBD'}')),
                            DataCell(_buildConsultationTypeChip((a['consultationType'] ?? 'In-Person').toString())),
                            DataCell(_buildStatusBadge((a['statusCategory'] ?? a['status'] ?? 'Pending').toString())),
                            DataCell(
                              refInfo != null
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _colReferrals.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Ref: ${refInfo['referringDoctorName'] ?? 'Referred'}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _colReferrals,
                                        ),
                                      ),
                                    )
                                  : const Text('—', style: TextStyle(color: AppTheme.textMuted)),
                            ),
                            DataCell(
                              TextButton.icon(
                                onPressed: () => _showAppointmentDetailDialog(a),
                                icon: const Icon(Icons.visibility_outlined, size: 16),
                                label: const Text('View'),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                if (totalPages > 1)
                  _buildPaginationBar(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalItems: totalItems,
                  ),
              ],
            ),
    );
  }

  Widget _buildMobileAppointmentCard(Map<String, dynamic> a) {
    final refInfo = a['referralInfo'] is Map
        ? Map<String, dynamic>.from(a['referralInfo'] as Map)
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (a['patientName'] ?? 'Patient').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusBadge((a['statusCategory'] ?? a['status'] ?? 'Pending').toString()),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Patient ID: ${a['patientId'] ?? 'N/A'}',
            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'Doctor: ${a['doctorName'] ?? 'Doctor'}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${a['appointmentDate'] ?? ''} • ${a['appointmentTime'] ?? 'TBD'}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMedium),
              ),
              _buildConsultationTypeChip((a['consultationType'] ?? 'In-Person').toString()),
              if (refInfo != null)
                _buildMiniStatPill('Ref: ${refInfo['referringDoctorName'] ?? 'Referred'}', _colReferrals),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _showAppointmentDetailDialog(a),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('View Details'),
            ),
          ),
        ],
      ),
    );
  }

  void _showAppointmentDetailDialog(Map<String, dynamic> a) {
    final refInfo = a['referralInfo'] is Map
        ? Map<String, dynamic>.from(a['referralInfo'] as Map)
        : null;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.event_note_rounded, color: AppTheme.gsNavy, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Appointment Details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDetailRow('Appointment ID', (a['appointmentId'] ?? 'N/A').toString()),
                  _buildDetailRow('Patient Name', (a['patientName'] ?? 'Patient').toString()),
                  _buildDetailRow('Patient ID', (a['patientId'] ?? 'N/A').toString()),
                  if ((a['patientPhone'] ?? '').toString().isNotEmpty)
                    _buildDetailRow('Patient Phone', a['patientPhone'].toString()),
                  _buildDetailRow('Doctor Name', (a['doctorName'] ?? 'Doctor').toString()),
                  _buildDetailRow('Specialty', (a['specialty'] ?? 'General Medicine').toString()),
                  if ((a['clinicName'] ?? '').toString().isNotEmpty)
                    _buildDetailRow('Clinic', a['clinicName'].toString()),
                  _buildDetailRow('Date', (a['appointmentDate'] ?? '').toString()),
                  _buildDetailRow('Time Slot', (a['appointmentTime'] ?? 'TBD').toString()),
                  _buildDetailRow('Consultation Type', (a['consultationType'] ?? 'In-Person').toString()),
                  _buildDetailRow('Status', (a['status'] ?? a['statusCategory'] ?? 'Pending').toString()),
                  _buildDetailRow('Treatment / Reason', (a['treatment'] ?? 'Medical Consultation').toString()),
                  if (refInfo != null) ...[
                    const Divider(height: 18),
                    const Text(
                      'Referral Information',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _colReferrals),
                    ),
                    const SizedBox(height: 6),
                    _buildDetailRow('Referral ID', (refInfo['referralId'] ?? 'N/A').toString()),
                    _buildDetailRow('Referred By', (refInfo['referringDoctorName'] ?? 'N/A').toString()),
                    _buildDetailRow('Referral Date', (refInfo['referralDate'] ?? 'N/A').toString()),
                    _buildDetailRow('Referral Status', (refInfo['referralStatus'] ?? 'Pending').toString()),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsNavy,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralsSection(bool isMobile) {
    final refs = _referrals;
    final totalItems = _intVal(_referralsPagination, 'totalItems');
    final totalPages = _intVal(_referralsPagination, 'totalPages').clamp(1, 9999);
    final currentPage = _intVal(_referralsPagination, 'page').clamp(1, totalPages);

    return _buildSectionContainer(
      title: 'Referral Tracking',
      subtitle: 'Referrals created or received on ${_formatReadableDate(_selectedDate)}',
      icon: Icons.group_add_rounded,
      badgeCount: totalItems > 0 ? totalItems : refs.length,
      headerTrailing: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _referralStatusOptions.map((st) {
          final selected = _selectedReferralStatus == st;
          return ChoiceChip(
            key: Key('doctor_calendar_ref_chip_${st.toLowerCase()}'),
            label: Text(st, style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            selected: selected,
            selectedColor: _colReferrals.withValues(alpha: 0.16),
            onSelected: (_) {
              setState(() {
                _selectedReferralStatus = st;
                _currentPage = 1;
              });
              _loadCalendarData();
            },
          );
        }).toList(),
      ),
      child: refs.isEmpty
          ? _buildEmptyState(
              icon: Icons.share_outlined,
              title: 'No referrals recorded',
              subtitle:
                  'No referrals match the selected filters on ${_formatReadableDate(_selectedDate)}.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isMobile)
                  Column(
                    children: refs.map(_buildMobileReferralCard).toList(),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      key: const Key('doctor_calendar_referrals_table'),
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                      columnSpacing: 18,
                      columns: const [
                        DataColumn(label: Text('Referral ID', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Referring Doctor', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Referred Doctor', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Patient Name', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Referral Date', style: TextStyle(fontWeight: FontWeight.w700))),
                        DataColumn(label: Text('Referral Status', style: TextStyle(fontWeight: FontWeight.w700))),
                      ],
                      rows: refs.map((r) {
                        final refId = (r['referralId'] ?? 'N/A').toString();
                        final shortRefId = refId.length > 12 ? '${refId.substring(0, 12)}…' : refId;
                        return DataRow(
                          cells: [
                            DataCell(Text(shortRefId, style: const TextStyle(fontSize: 12, color: AppTheme.textMedium))),
                            DataCell(Text((r['referringDoctorName'] ?? 'N/A').toString())),
                            DataCell(Text((r['referredDoctorName'] ?? 'Unassigned').toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text((r['patientName'] ?? 'Patient').toString())),
                            DataCell(Text((r['referralDate'] ?? '').toString())),
                            DataCell(_buildStatusBadge((r['referralStatus'] ?? 'Pending').toString())),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                if (totalPages > 1)
                  _buildPaginationBar(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalItems: totalItems,
                  ),
              ],
            ),
    );
  }

  Widget _buildMobileReferralCard(Map<String, dynamic> r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (r['patientName'] ?? 'Patient').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusBadge((r['referralStatus'] ?? 'Pending').toString()),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ref ID: ${r['referralId'] ?? 'N/A'} • ${r['referralDate'] ?? ''}',
            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'From: ${r['referringDoctorName'] ?? 'N/A'} → To: ${r['referredDoctorName'] ?? 'Unassigned'}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar({
    required int currentPage,
    required int totalPages,
    required int totalItems,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              'Page $currentPage of $totalPages ($totalItems total)',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: currentPage > 1
                    ? () {
                        setState(() => _currentPage = currentPage - 1);
                        _loadCalendarData();
                      }
                    : null,
                child: const Text('Previous'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: currentPage < totalPages
                    ? () {
                        setState(() => _currentPage = currentPage + 1);
                        _loadCalendarData();
                      }
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContainer({
    required String title,
    required String subtitle,
    required IconData icon,
    required int badgeCount,
    Widget? headerTrailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, color: AppTheme.gsNavy, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.gsNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$badgeCount',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.gsNavy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (headerTrailing != null) ...[
            const SizedBox(height: 10),
            headerTrailing,
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildConsultationTypeChip(String type) {
    final isOnline = type.toLowerCase().contains('online');
    final color = isOnline ? const Color(0xFF0284C7) : const Color(0xFF0F766E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        type,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final lower = status.trim().toLowerCase();
    Color bg;
    Color fg;
    if (lower == 'completed' || lower == 'accepted' || lower == 'confirmed') {
      bg = _colCompleted.withValues(alpha: 0.12);
      fg = _colCompleted;
    } else if (lower == 'cancelled' || lower == 'rejected') {
      bg = _colCancelled.withValues(alpha: 0.12);
      fg = _colCancelled;
    } else {
      bg = _colPending.withValues(alpha: 0.14);
      fg = _colPending;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildMiniStatPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        children: [
          CircularProgressIndicator(color: AppTheme.gsNavy),
          SizedBox(height: 12),
          Text(
            'Loading Doctor Activity Calendar...',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.textMedium),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      key: const Key('doctor_calendar_error_card'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _colCancelled.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: _colCancelled, size: 38),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? 'Unable to load Doctor Activity Calendar.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            key: const Key('doctor_calendar_retry_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gsNavy,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _loadCalendarData(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineWarningBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _colCancelled.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _colCancelled.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _colCancelled, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, color: _colCancelled, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => _loadCalendarData(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppTheme.textMuted.withValues(alpha: 0.65)),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
