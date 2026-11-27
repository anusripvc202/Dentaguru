import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';

/// GS Health Admin — Calendar View for Requests & Referrals
///
/// Features:
/// - Monthly Calendar (Previous Month, Next Month, Today button, current date & selected date highlights)
/// - Separate visual indicators and counts inside calendar dates for Requests and Referrals + color legend
/// - Selected Date — 8 Daily Summary Cards (Total/Pending/Approved/Rejected Requests + Total/Pending/Accepted/Completed Referrals)
/// - Daily Requests Details (Request ID, Patient Name, Doctor Name, Request Type, Date & Time, Status, View Details modal)
/// - Daily Referrals Details (Referral ID, Patient Name, Referring Doctor, Referred Doctor, Date & Time, Status, View Details modal)
/// - Combined Search (Request ID, Referral ID, Patient Name, Doctor Name) + Request Status + Request Type + Referral Status filters + Clear Filters + Pagination
class AdminRequestsReferralsCalendarView extends StatefulWidget {
  final PatientProblemService problemService;
  final DateTime? initialDate;

  const AdminRequestsReferralsCalendarView({
    super.key,
    required this.problemService,
    this.initialDate,
  });

  @override
  State<AdminRequestsReferralsCalendarView> createState() =>
      _AdminRequestsReferralsCalendarViewState();
}

class _AdminRequestsReferralsCalendarViewState
    extends State<AdminRequestsReferralsCalendarView> {
  static const List<String> _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const List<String> _requestStatusOptions = [
    'All',
    'Pending',
    'Approved',
    'Rejected',
  ];
  static const List<String> _referralStatusOptions = [
    'All',
    'Pending',
    'Accepted',
    'Completed',
    'Rejected',
  ];

  // Distinct visual colors for Requests vs Referrals
  static const Color _colRequests = Color(0xFF2563EB); // Royal Blue
  static const Color _colReferrals = Color(0xFF7C3AED); // Purple
  static const Color _colApproved = Color(0xFF059669); // Emerald Green
  static const Color _colPending = Color(0xFFD97706); // Amber
  static const Color _colRejected = Color(0xFFDC2626); // Red

  late DateTime _selectedDate;
  late DateTime _displayedMonth;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _selectedRequestStatus = 'All';
  String _selectedRequestType = 'All';
  String _selectedReferralStatus = 'All';

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

    final res = await ApiService().fetchAdminRequestsReferralsCalendar(
      date: _formatYmd(_selectedDate),
      month: _formatYm(_displayedMonth),
      search: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
      requestStatus: _selectedRequestStatus == 'All' ? null : _selectedRequestStatus,
      requestType: _selectedRequestType == 'All' ? null : _selectedRequestType,
      referralStatus: _selectedReferralStatus == 'All' ? null : _selectedReferralStatus,
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
        _errorMessage = (res['message'] ?? 'Unable to load Requests & Referrals Calendar.').toString();
      });
    }
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedDate = today;
      _displayedMonth = DateTime(today.year, today.month, 1);
      _currentPage = 1;
    });
    _loadCalendarData();
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _currentPage = 1;
    });
    _loadCalendarData();
  }

  void _clearAllFilters() {
    _searchDebounce?.cancel();
    setState(() {
      _searchController.clear();
      _selectedRequestStatus = 'All';
      _selectedRequestType = 'All';
      _selectedReferralStatus = 'All';
      _currentPage = 1;
    });
    _loadCalendarData();
  }

  bool get _hasActiveFilters =>
      _searchController.text.trim().isNotEmpty ||
      _selectedRequestStatus != 'All' ||
      _selectedRequestType != 'All' ||
      _selectedReferralStatus != 'All';

  List<String> get _availableRequestTypes {
    final set = <String>{'All'};
    final rawDirect = _calendarData?['requestTypes'];
    if (rawDirect is List) {
      for (final item in rawDirect) {
        final s = (item ?? '').toString().trim();
        if (s.isNotEmpty) set.add(s);
      }
    }
    final filterOpts = _calendarData?['filterOptions'];
    if (filterOpts is Map && filterOpts['requestTypes'] is List) {
      for (final item in (filterOpts['requestTypes'] as List)) {
        final s = (item ?? '').toString().trim();
        if (s.isNotEmpty) set.add(s);
      }
    }
    return set.toList();
  }

  Map<String, Map<String, dynamic>> get _monthlyMapByDate {
    final map = <String, Map<String, dynamic>>{};
    final rawCal = _calendarData?['monthlyCalendar'];
    if (rawCal is Map) {
      rawCal.forEach((key, value) {
        final d = key.toString().trim();
        if (d.isNotEmpty && value is Map) {
          map[d] = Map<String, dynamic>.from(value);
        }
      });
    } else if (rawCal is List) {
      for (final raw in rawCal) {
        if (raw is Map) {
          final d = (raw['date'] ?? '').toString().trim();
          if (d.isNotEmpty) {
            map[d] = Map<String, dynamic>.from(raw);
          }
        }
      }
    }
    return map;
  }

  Map<String, dynamic> get _dailySummary {
    final raw = _calendarData?['dailySummary'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> get _dailyRequests {
    final raw = _calendarData?['requests'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> get _dailyReferrals {
    final raw = _calendarData?['referrals'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  int _intVal(dynamic v) => int.tryParse((v ?? '0').toString()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final requestTypes = _availableRequestTypes;
    final effectiveRequestType =
        requestTypes.contains(_selectedRequestType) ? _selectedRequestType : 'All';

    return Column(
      key: const Key('admin_requests_referrals_calendar_root'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Search & Combined Filter Bar
        _buildFilterBar(requestTypes, effectiveRequestType),
        const SizedBox(height: 16),

        // 2. Monthly Calendar Card with Separate Requests & Referrals Indicators
        _buildMonthlyCalendarCard(),
        const SizedBox(height: 18),

        // 3. Selected Date Banner
        _buildSelectedDateHeader(),
        const SizedBox(height: 12),

        if (_errorMessage != null && _calendarData == null)
          _buildErrorCard()
        else if (_isLoading && _calendarData == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: AppTheme.gsNavy)),
          )
        else ...[
          // 4. Selected Date — 8 Summary Cards (4 Requests + 4 Referrals)
          _buildSummaryCardsGrid(),
          const SizedBox(height: 20),

          // 5. Daily Requests Details Section
          _buildDailyRequestsSection(),
          const SizedBox(height: 20),

          // 6. Daily Referrals Details Section
          _buildDailyReferralsSection(),
          const SizedBox(height: 16),

          // 7. Pagination Footer
          _buildPaginationBar(),
        ],
      ],
    );
  }

  Widget _buildFilterBar(List<String> requestTypes, String effectiveRequestType) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              key: const Key('req_ref_cal_search_field'),
              controller: _searchController,
              onChanged: (_) {
                _searchDebounce?.cancel();
                setState(() => _currentPage = 1);
                _searchDebounce = Timer(const Duration(milliseconds: 220), _loadCalendarData);
              },
              decoration: InputDecoration(
                hintText: 'Search Request/Referral ID, Patient, or Doctor...',
                hintStyle: const TextStyle(fontSize: 12.5),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              key: const Key('req_ref_cal_request_status_filter'),
              initialValue: _selectedRequestStatus,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Request Status',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _requestStatusOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedRequestStatus = v;
                    _currentPage = 1;
                  });
                  _loadCalendarData();
                }
              },
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              key: const Key('req_ref_cal_request_type_filter'),
              initialValue: effectiveRequestType,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Request Type',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: requestTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedRequestType = v;
                    _currentPage = 1;
                  });
                  _loadCalendarData();
                }
              },
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              key: const Key('req_ref_cal_referral_status_filter'),
              initialValue: _selectedReferralStatus,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Referral Status',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _referralStatusOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedReferralStatus = v;
                    _currentPage = 1;
                  });
                  _loadCalendarData();
                }
              },
            ),
          ),
          if (_hasActiveFilters)
            TextButton.icon(
              key: const Key('req_ref_cal_clear_filters_btn'),
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16, color: AppTheme.gsRed),
              label: const Text(
                'Clear Filters',
                style: TextStyle(color: AppTheme.gsRed, fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthlyCalendarCard() {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingEmptyCells = firstDayOfMonth.weekday % 7; // Sunday = 0
    final totalCells = ((leadingEmptyCells + daysInMonth + 6) ~/ 7) * 7;

    final now = DateTime.now();
    final todayYmd = _formatYmd(DateTime(now.year, now.month, now.day));
    final selectedYmd = _formatYmd(_selectedDate);
    final monthMap = _monthlyMapByDate;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Month Navigation & Legend Row
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('req_ref_cal_prev_month_btn'),
                    tooltip: 'Previous Month',
                    onPressed: _goToPreviousMonth,
                    icon: const Icon(Icons.chevron_left_rounded, color: AppTheme.gsNavy),
                  ),
                  Text(
                    '${_monthNames[month - 1]} $year',
                    key: const Key('req_ref_cal_month_title'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.gsNavy,
                    ),
                  ),
                  IconButton(
                    key: const Key('req_ref_cal_next_month_btn'),
                    tooltip: 'Next Month',
                    onPressed: _goToNextMonth,
                    icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.gsNavy),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    key: const Key('req_ref_cal_today_btn'),
                    onPressed: _goToToday,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.gsNavy,
                      side: const BorderSide(color: AppTheme.gsNavy),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              // Legend for Requests vs Referrals
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _buildLegendDot(_colRequests, 'Requests'),
                  _buildLegendDot(_colReferrals, 'Referrals'),
                  _buildLegendDot(AppTheme.gsRed, 'Today'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Weekday Headers (Sun - Sat)
          Row(
            children: _weekdays
                .map(
                  (w) => Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),

          // Calendar Days Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 560;
              final rows = <Widget>[];
              for (int week = 0; week < totalCells ~/ 7; week++) {
                final cells = <Widget>[];
                for (int dow = 0; dow < 7; dow++) {
                  final cellIndex = week * 7 + dow;
                  final dayNumber = cellIndex - leadingEmptyCells + 1;
                  if (dayNumber < 1 || dayNumber > daysInMonth) {
                    cells.add(const Expanded(child: SizedBox(height: 68)));
                    continue;
                  }
                  final cellDate = DateTime(year, month, dayNumber);
                  final dateYmd = _formatYmd(cellDate);
                  final isSelected = dateYmd == selectedYmd;
                  final isToday = dateYmd == todayYmd;
                  final dayStats = monthMap[dateYmd];
                  final reqCount = _intVal(dayStats?['requestsCount']);
                  final refCount = _intVal(dayStats?['referralsCount']);

                  cells.add(
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(2.5),
                        child: InkWell(
                          key: Key('req_ref_cal_day_$dateYmd'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _selectDate(cellDate),
                          child: Container(
                            constraints: BoxConstraints(minHeight: isCompact ? 62 : 76),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.gsNavy.withValues(alpha: 0.09)
                                  : (isToday
                                      ? AppTheme.gsRed.withValues(alpha: 0.06)
                                      : const Color(0xFFF8FAFC)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.gsNavy
                                    : (isToday ? AppTheme.gsRed : const Color(0xFFE2E8F0)),
                                width: (isSelected || isToday) ? 1.6 : 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '$dayNumber',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: (isSelected || isToday)
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: isSelected
                                            ? AppTheme.gsNavy
                                            : (isToday ? AppTheme.gsRed : AppTheme.textDark),
                                      ),
                                    ),
                                    if (reqCount > 0 || refCount > 0)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (reqCount > 0)
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: const BoxDecoration(
                                                color: _colRequests,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          if (reqCount > 0 && refCount > 0)
                                            const SizedBox(width: 3),
                                          if (refCount > 0)
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: const BoxDecoration(
                                                color: _colReferrals,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                if (reqCount > 0)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 2),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: _colRequests.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      isCompact ? 'Req: $reqCount' : 'Requests: $reqCount',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: _colRequests,
                                      ),
                                    ),
                                  ),
                                if (refCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: _colReferrals.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      isCompact ? 'Ref: $refCount' : 'Referrals: $refCount',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: _colReferrals,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                rows.add(Row(children: cells));
              }
              return Column(children: rows);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMedium),
        ),
      ],
    );
  }

  Widget _buildSelectedDateHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.gsNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gsNavy.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_note_rounded, color: AppTheme.gsNavy, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Daily Requests & Referrals — ${_formatReadableDate(_selectedDate)} (${_formatYmd(_selectedDate)})',
              key: const Key('req_ref_cal_selected_date_label'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppTheme.gsNavy,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gsNavy),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCardsGrid() {
    final s = _dailySummary;
    final cards = <({Key key, String label, int value, Color color, IconData icon})>[
      (
        key: const Key('req_ref_summary_total_requests'),
        label: 'Total Requests',
        value: _intVal(s['totalRequests']),
        color: _colRequests,
        icon: Icons.medical_information_outlined,
      ),
      (
        key: const Key('req_ref_summary_pending_requests'),
        label: 'Pending Requests',
        value: _intVal(s['pendingRequests']),
        color: _colPending,
        icon: Icons.pending_actions_rounded,
      ),
      (
        key: const Key('req_ref_summary_approved_requests'),
        label: 'Approved Requests',
        value: _intVal(s['approvedRequests']),
        color: _colApproved,
        icon: Icons.check_circle_outline_rounded,
      ),
      (
        key: const Key('req_ref_summary_rejected_requests'),
        label: 'Rejected Requests',
        value: _intVal(s['rejectedRequests']),
        color: _colRejected,
        icon: Icons.cancel_outlined,
      ),
      (
        key: const Key('req_ref_summary_total_referrals'),
        label: 'Total Referrals',
        value: _intVal(s['totalReferrals']),
        color: _colReferrals,
        icon: Icons.share_outlined,
      ),
      (
        key: const Key('req_ref_summary_pending_referrals'),
        label: 'Pending Referrals',
        value: _intVal(s['pendingReferrals']),
        color: _colPending,
        icon: Icons.schedule_rounded,
      ),
      (
        key: const Key('req_ref_summary_accepted_referrals'),
        label: 'Accepted Referrals',
        value: _intVal(s['acceptedReferrals']),
        color: _colRequests,
        icon: Icons.thumb_up_alt_outlined,
      ),
      (
        key: const Key('req_ref_summary_completed_referrals'),
        label: 'Completed Referrals',
        value: _intVal(s['completedReferrals']),
        color: _colApproved,
        icon: Icons.task_alt_rounded,
      ),
    ];

    return LayoutBuilder(
      key: const Key('req_ref_cal_summary_grid'),
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 900 ? 4 : (constraints.maxWidth >= 520 ? 2 : 2);
        const spacing = 10.0;
        final itemWidth = (constraints.maxWidth - (spacing * (cols - 1))) / cols;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((c) {
            return Container(
              key: c.key,
              width: itemWidth,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.color.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(c.icon, color: c.color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.value}',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: c.color,
                          ),
                        ),
                        Text(
                          c.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDailyRequestsSection() {
    final requests = _dailyRequests;
    return Container(
      key: const Key('req_ref_cal_daily_requests_section'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medical_information_outlined, color: _colRequests, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Daily Requests Details (${requests.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (requests.isEmpty)
            Container(
              key: const Key('req_ref_cal_requests_empty'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                'No requests created on this date.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
              ),
            )
          else
            Column(
              children: requests.map((req) {
                final reqId = (req['requestId'] ?? '').toString();
                final pName = (req['patientName'] ?? 'Patient').toString();
                final dName = (req['doctorName'] ?? 'Unassigned').toString();
                final rType = (req['requestType'] ?? 'Consultation').toString();
                final rDate = (req['requestDate'] ?? '').toString();
                final rTime = (req['requestTime'] ?? '').toString();
                final rStatus = (req['status'] ?? 'Pending').toString();
                final stColor = rStatus == 'Approved'
                    ? _colApproved
                    : (rStatus == 'Rejected' ? _colRejected : _colPending);

                return Container(
                  key: Key('req_ref_request_item_$reqId'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  pName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: stColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    rStatus,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: stColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Request ID: $reqId • Type: $rType',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMedium),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Doctor: $dName • Created: $rDate${rTime.isNotEmpty ? " at $rTime" : ""}',
                              style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: Key('req_ref_view_request_$reqId'),
                        onPressed: () => _showRequestDetailsDialog(req),
                        icon: const Icon(Icons.visibility_outlined, size: 15),
                        label: const Text('View Details', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildDailyReferralsSection() {
    final referrals = _dailyReferrals;
    return Container(
      key: const Key('req_ref_cal_daily_referrals_section'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.share_outlined, color: _colReferrals, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Daily Referrals Details (${referrals.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (referrals.isEmpty)
            Container(
              key: const Key('req_ref_cal_referrals_empty'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                'No referrals created on this date.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
              ),
            )
          else
            Column(
              children: referrals.map((ref) {
                final refId = (ref['referralId'] ?? '').toString();
                final pName = (ref['patientName'] ?? 'Patient').toString();
                final referringDoc = (ref['referringDoctorName'] ?? 'Referrer').toString();
                final referredDoc = (ref['referredDoctorName'] ?? 'Specialist').toString();
                final rDate = (ref['referralDate'] ?? '').toString();
                final rTime = (ref['referralTime'] ?? '').toString();
                final rStatus = (ref['status'] ?? 'Pending').toString();
                final stColor = (rStatus == 'Accepted' || rStatus == 'Completed')
                    ? _colApproved
                    : (rStatus == 'Rejected' ? _colRejected : _colPending);

                return Container(
                  key: Key('req_ref_referral_item_$refId'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  pName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: stColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    rStatus,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: stColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Referral ID: $refId • Referring Doctor: $referringDoc → Referred Doctor: $referredDoc',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMedium),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Created: $rDate${rTime.isNotEmpty ? " at $rTime" : ""}',
                              style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: Key('req_ref_view_referral_$refId'),
                        onPressed: () => _showReferralDetailsDialog(ref),
                        icon: const Icon(Icons.visibility_outlined, size: 15),
                        label: const Text('View Details', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar() {
    final reqPag = _calendarData?['requestsPagination'] is Map
        ? Map<String, dynamic>.from(_calendarData!['requestsPagination'] as Map)
        : const <String, dynamic>{};
    final refPag = _calendarData?['referralsPagination'] is Map
        ? Map<String, dynamic>.from(_calendarData!['referralsPagination'] as Map)
        : const <String, dynamic>{};
    final reqPages = _intVal(reqPag['totalPages']);
    final refPages = _intVal(refPag['totalPages']);
    final maxPages = reqPages > refPages ? reqPages : refPages;

    if (maxPages <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Page $_currentPage of $maxPages',
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        Row(
          children: [
            OutlinedButton(
              onPressed: _currentPage > 1
                  ? () {
                      setState(() => _currentPage -= 1);
                      _loadCalendarData();
                    }
                  : null,
              child: const Text('Previous'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _currentPage < maxPages
                  ? () {
                      setState(() => _currentPage += 1);
                      _loadCalendarData();
                    }
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.gsRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gsRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.gsRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? 'Unable to load calendar data.',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark),
            ),
          ),
          TextButton(
            onPressed: _loadCalendarData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showRequestDetailsDialog(Map<String, dynamic> req) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Request Details', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Request ID', (req['requestId'] ?? '—').toString()),
              _detailRow('Patient Name', (req['patientName'] ?? '—').toString()),
              _detailRow('Patient Phone', (req['patientPhone'] ?? '—').toString()),
              _detailRow('Assigned Doctor', (req['doctorName'] ?? 'Unassigned').toString()),
              _detailRow('Request Type', (req['requestType'] ?? '—').toString()),
              _detailRow(
                'Request Date & Time',
                '${req['requestDate'] ?? ''} ${(req['requestTime'] ?? '').toString().trim()}'.trim(),
              ),
              _detailRow('Request Status', (req['status'] ?? '—').toString()),
              if ((req['problemDescription'] ?? '').toString().trim().isNotEmpty)
                _detailRow('Description', req['problemDescription'].toString()),
              if ((req['symptoms'] ?? '').toString().trim().isNotEmpty)
                _detailRow('Symptoms', req['symptoms'].toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showReferralDetailsDialog(Map<String, dynamic> ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Referral Details', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Referral ID', (ref['referralId'] ?? '—').toString()),
              _detailRow('Patient Name', (ref['patientName'] ?? '—').toString()),
              _detailRow('Patient Phone', (ref['patientPhone'] ?? '—').toString()),
              _detailRow('Referring Doctor', (ref['referringDoctorName'] ?? '—').toString()),
              _detailRow('Referred Doctor', (ref['referredDoctorName'] ?? '—').toString()),
              _detailRow('Required Specialist', (ref['requiredSpecialist'] ?? '—').toString()),
              _detailRow(
                'Referral Date & Time',
                '${ref['referralDate'] ?? ''} ${(ref['referralTime'] ?? '').toString().trim()}'.trim(),
              ),
              _detailRow('Referral Status', (ref['status'] ?? '—').toString()),
              if ((ref['clinicalComplaint'] ?? '').toString().trim().isNotEmpty)
                _detailRow('Clinical Notes', ref['clinicalComplaint'].toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '—',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
