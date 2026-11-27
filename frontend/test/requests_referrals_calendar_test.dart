import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_referrals_screen.dart';
import 'package:dentaguru/features/admin/presentation/widgets/admin_requests_referrals_calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, dynamic>> buildMockCalendarResponse({
    required String date,
    required String month,
    String? search,
    String? requestStatus,
    String? requestType,
    String? referralStatus,
    int page = 1,
    int pageSize = 20,
  }) async {
    final allRequestsFor15 = <Map<String, dynamic>>[
      {
        'id': 'REQ-1001',
        'requestId': 'REQ-1001',
        'patientName': 'Aarav Sharma',
        'patientMobile': '9876543210',
        'doctorName': 'Dr. Priya Nair',
        'doctorSpecialty': 'Orthodontics',
        'doctorClinic': 'Smile Care Clinic',
        'requestType': 'Dental Pain Consultation',
        'symptoms': 'Severe molar pain and sensitivity',
        'duration': '3 days',
        'severity': 'High',
        'requestDate': '2026-11-15',
        'requestDateTime': '2026-11-15T10:30:00.000Z',
        'requestTimeFormatted': '04:00 PM',
        'rawStatus': 'Pending Admin Review',
        'status': 'Pending',
        'city': 'Hyderabad',
        'state': 'Telangana',
        'pincode': '500081',
      },
      {
        'id': 'REQ-1002',
        'requestId': 'REQ-1002',
        'patientName': 'Meera Reddy',
        'patientMobile': '9876500011',
        'doctorName': 'Dr. Karthik Rao',
        'doctorSpecialty': 'Endodontics',
        'doctorClinic': 'Apex Dental Center',
        'requestType': 'Root Canal Evaluation',
        'symptoms': 'Swelling near lower premolar',
        'duration': '5 days',
        'severity': 'Moderate',
        'requestDate': '2026-11-15',
        'requestDateTime': '2026-11-15T12:00:00.000Z',
        'requestTimeFormatted': '05:30 PM',
        'rawStatus': 'Doctor Assigned',
        'status': 'Approved',
        'city': 'Hyderabad',
        'state': 'Telangana',
        'pincode': '500032',
      },
    ];

    final allReferralsFor15 = <Map<String, dynamic>>[
      {
        'id': 'REF-2001',
        'referralId': 'REF-2001',
        'patientName': 'Rohan Verma',
        'patientMobile': '9123456780',
        'patientCity': 'Hyderabad',
        'referringDoctorName': 'Dr. Suresh Babu',
        'referredDoctorName': 'Dr. Ananya Menon',
        'referredDoctorSpecialty': 'Oral Surgery',
        'referredDoctorClinic': 'Metro Oral Care',
        'clinicalComplaint': 'Impacted wisdom tooth extraction',
        'notes': 'Panoramic X-ray attached',
        'urgency': 'Urgent',
        'referralDate': '2026-11-15',
        'referralDateTime': '2026-11-15T09:15:00.000Z',
        'referralTimeFormatted': '02:45 PM',
        'rawStatus': 'Accepted',
        'status': 'Accepted',
      },
      {
        'id': 'REF-2002',
        'referralId': 'REF-2002',
        'patientName': 'Kavya Krishnan',
        'patientMobile': '9988776655',
        'patientCity': 'Secunderabad',
        'referringDoctorName': 'Dr. Priya Nair',
        'referredDoctorName': 'Dr. Vikram Sethi',
        'referredDoctorSpecialty': 'Periodontics',
        'referredDoctorClinic': 'Perio Health Hub',
        'clinicalComplaint': 'Periodontal flap surgery consultation',
        'notes': 'Follow-up after scaling',
        'urgency': 'Routine',
        'referralDate': '2026-11-15',
        'referralDateTime': '2026-11-15T14:00:00.000Z',
        'referralTimeFormatted': '07:30 PM',
        'rawStatus': 'Completed',
        'status': 'Completed',
      },
    ];

    final isTargetDate = date == '2026-11-15';
    final dateReqs = isTargetDate ? allRequestsFor15 : <Map<String, dynamic>>[];
    final dateRefs = isTargetDate ? allReferralsFor15 : <Map<String, dynamic>>[];

    final q = (search ?? '').trim().toLowerCase();
    final filteredReqs = dateReqs.where((r) {
      if (requestStatus != null &&
          requestStatus != 'All' &&
          r['status'].toString().toLowerCase() != requestStatus.toLowerCase()) {
        return false;
      }
      if (requestType != null &&
          requestType != 'All' &&
          r['requestType'].toString().toLowerCase() != requestType.toLowerCase()) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = '${r['requestId']} ${r['patientName']} ${r['doctorName']} ${r['requestType']}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    final filteredRefs = dateRefs.where((r) {
      if (referralStatus != null &&
          referralStatus != 'All' &&
          r['status'].toString().toLowerCase() != referralStatus.toLowerCase()) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = '${r['referralId']} ${r['patientName']} ${r['referringDoctorName']} ${r['referredDoctorName']}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    return {
      'success': true,
      'selectedDate': date,
      'month': month,
      'timezone': 'Asia/Kolkata',
      'monthlyCalendar': {
        '2026-11-15': {
          'date': '2026-11-15',
          'requestsCount': 2,
          'referralsCount': 2,
          'totalActivityCount': 4,
        },
        '2026-11-16': {
          'date': '2026-11-16',
          'requestsCount': 3,
          'referralsCount': 0,
          'totalActivityCount': 3,
        },
        '2026-11-17': {
          'date': '2026-11-17',
          'requestsCount': 0,
          'referralsCount': 1,
          'totalActivityCount': 1,
        },
      },
      'dailySummary': {
        'totalRequests': dateReqs.length,
        'pendingRequests': dateReqs.where((r) => r['status'] == 'Pending').length,
        'approvedRequests': dateReqs.where((r) => r['status'] == 'Approved').length,
        'rejectedRequests': dateReqs.where((r) => r['status'] == 'Rejected').length,
        'totalReferrals': dateRefs.length,
        'pendingReferrals': dateRefs.where((r) => r['status'] == 'Pending').length,
        'acceptedReferrals': dateRefs.where((r) => r['status'] == 'Accepted').length,
        'completedReferrals': dateRefs.where((r) => r['status'] == 'Completed').length,
        'rejectedReferrals': dateRefs.where((r) => r['status'] == 'Rejected').length,
      },
      'filterOptions': {
        'requestStatuses': ['All', 'Pending', 'Approved', 'Rejected'],
        'requestTypes': [
          'All',
          'Dental Pain Consultation',
          'Root Canal Evaluation',
        ],
        'referralStatuses': ['All', 'Pending', 'Accepted', 'Completed', 'Rejected'],
      },
      'requests': filteredReqs,
      'referrals': filteredRefs,
      'pagination': {
        'page': page,
        'pageSize': pageSize,
        'totalRequestsFiltered': filteredReqs.length,
        'totalReferralsFiltered': filteredRefs.length,
        'totalRequestPages': 1,
        'totalReferralPages': 1,
      },
    };
  }

  setUp(() {
    ApiService.debugRequestsReferralsCalendarOverride = buildMockCalendarResponse;
  });

  tearDown(() {
    ApiService.debugRequestsReferralsCalendarOverride = null;
  });

  testWidgets(
      'AdminRequestsReferralsCalendarView displays monthly indicators, 8 summary cards, daily requests/referrals, filters and View Details modals',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminRequestsReferralsCalendarView(
              problemService: PatientProblemService(),
              initialDate: DateTime(2026, 11, 15),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify Monthly Calendar header & date indicators
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.byKey(const Key('req_ref_cal_day_2026-11-15')), findsOneWidget);
    expect(find.text('Requests: 2'), findsOneWidget);
    expect(find.text('Referrals: 2'), findsOneWidget);
    expect(find.text('Requests: 3'), findsOneWidget);
    expect(find.text('Referrals: 1'), findsOneWidget);

    // 2. Verify all 8 Daily Summary Cards
    expect(find.byKey(const Key('req_ref_summary_total_requests')), findsOneWidget);
    expect(find.byKey(const Key('req_ref_summary_pending_requests')), findsOneWidget);
    expect(find.byKey(const Key('req_ref_summary_approved_requests')), findsOneWidget);
    expect(find.byKey(const Key('req_ref_summary_rejected_requests')), findsOneWidget);
    expect(find.byKey(const Key('req_ref_summary_total_referrals')), findsOneWidget);
    expect(find.byKey(const Key('req_ref_summary_pending_referrals')), findsOneWidget);
    expect(find.byKey(const Key('req_ref_summary_accepted_referrals')), findsOneWidget);
    expect(find.byKey(const Key('req_ref_summary_completed_referrals')), findsOneWidget);

    // 3. Verify Daily Requests & Daily Referrals rows are rendered
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Meera Reddy'), findsOneWidget);
    expect(find.text('Rohan Verma'), findsOneWidget);
    expect(find.text('Kavya Krishnan'), findsOneWidget);

    // 4. Open Request View Details dialog
    await tester.tap(find.byKey(const Key('req_ref_view_request_REQ-1001')));
    await tester.pumpAndSettle();
    expect(find.text('Request Details'), findsOneWidget);
    expect(find.text('Severe molar pain and sensitivity'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // 5. Open Referral View Details dialog
    await tester.tap(find.byKey(const Key('req_ref_view_referral_REF-2001')));
    await tester.pumpAndSettle();
    expect(find.text('Referral Details'), findsOneWidget);
    expect(find.text('Impacted wisdom tooth extraction'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // 6. Click a date with NO records (2026-11-20) and verify empty states
    await tester.tap(find.byKey(const Key('req_ref_cal_day_2026-11-20')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('req_ref_cal_requests_empty')), findsOneWidget);
    expect(find.byKey(const Key('req_ref_cal_referrals_empty')), findsOneWidget);

    // 7. Navigate Previous Month and Next Month
    await tester.tap(find.byKey(const Key('req_ref_cal_prev_month_btn')));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('req_ref_cal_next_month_btn')));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
  });

  testWidgets(
      'AdminReferralsScreen allows switching between List View and Calendar View seamlessly',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: AdminReferralsScreen(),
      ),
    );
    await tester.pump();

    // Initially in List View
    expect(find.byKey(const Key('admin_referrals_screen_list_view_btn')), findsOneWidget);
    expect(find.byKey(const Key('admin_referrals_screen_calendar_view_btn')), findsOneWidget);
    expect(find.byKey(const Key('admin_requests_referrals_calendar_root')), findsNothing);

    // Switch to Calendar View
    await tester.tap(find.byKey(const Key('admin_referrals_screen_calendar_view_btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin_requests_referrals_calendar_root')), findsOneWidget);

    // Switch back to List View
    await tester.tap(find.byKey(const Key('admin_referrals_screen_list_view_btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin_requests_referrals_calendar_root')), findsNothing);
  });
}
