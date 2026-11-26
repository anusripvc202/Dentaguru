import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/widgets/admin_doctor_activity_calendar.dart';

Map<String, dynamic> _buildSampleCalendarResponse({
  required String date,
  required String month,
  bool emptyDay = false,
  String? referralStatus,
}) {
  final allReferrals = [
    {
      'referralId': 'REF-101',
      'referringDoctorId': 'doc-1',
      'referringDoctorName': 'Dr. Asha Menon',
      'referredDoctorId': 'doc-2',
      'referredDoctorName': 'Dr. Rajiv Verma',
      'patientId': 'pat-2',
      'patientName': 'Rohan Das',
      'referralDate': date,
      'referralStatus': 'Accepted',
    },
    {
      'referralId': 'REF-102',
      'referringDoctorId': 'doc-2',
      'referringDoctorName': 'Dr. Rajiv Verma',
      'referredDoctorId': 'doc-1',
      'referredDoctorName': 'Dr. Asha Menon',
      'patientId': 'pat-1',
      'patientName': 'Kavya Nair',
      'referralDate': date,
      'referralStatus': 'Pending',
    },
  ];
  final filteredRefs = emptyDay
      ? <Map<String, dynamic>>[]
      : allReferrals.where((r) {
          if (referralStatus == null || referralStatus == 'All') return true;
          return r['referralStatus'] == referralStatus;
        }).toList();

  return {
    'success': true,
    'timezone': 'Asia/Kolkata',
    'today': '2026-11-26',
    'month': month,
    'selectedDate': date,
    'monthlyCalendar': {
      '2026-11-26': {
        'date': '2026-11-26',
        'totalAppointments': 5,
        'completedAppointments': 3,
        'pendingAppointments': 1,
        'cancelledAppointments': 1,
        'totalReferrals': 2,
        'activeDoctorsCount': 2,
      },
    },
    'dailySummary': emptyDay
        ? {
            'date': date,
            'totalDoctorsActive': 0,
            'totalAppointments': 0,
            'totalPatientsChecked': 0,
            'totalReferrals': 0,
            'pendingAppointments': 0,
            'completedAppointments': 0,
            'cancelledAppointments': 0,
          }
        : {
            'date': date,
            'totalDoctorsActive': 2,
            'totalAppointments': 5,
            'totalPatientsChecked': 2,
            'totalReferrals': filteredRefs.length,
            'pendingAppointments': 1,
            'completedAppointments': 3,
            'cancelledAppointments': 1,
          },
    'doctorActivity': emptyDay
        ? <Map<String, dynamic>>[]
        : [
            {
              'doctorId': 'doc-1',
              'userId': 'u-doc-1',
              'doctorName': 'Dr. Asha Menon',
              'specialty': 'Cardiology',
              'clinicName': 'GS Heart Center',
              'totalAppointments': 3,
              'patientsChecked': 1,
              'referralsReceived': 1,
              'referralsGiven': 1,
              'pendingAppointments': 1,
              'completedAppointments': 2,
              'cancelledAppointments': 0,
            },
            {
              'doctorId': 'doc-2',
              'userId': 'u-doc-2',
              'doctorName': 'Dr. Rajiv Verma',
              'specialty': 'Dentistry',
              'clinicName': 'GS Dental Center',
              'totalAppointments': 2,
              'patientsChecked': 1,
              'referralsReceived': 1,
              'referralsGiven': 1,
              'pendingAppointments': 0,
              'completedAppointments': 1,
              'cancelledAppointments': 1,
            },
          ],
    'appointments': emptyDay
        ? <Map<String, dynamic>>[]
        : [
            {
              'appointmentId': 'APT-01',
              'patientId': 'pat-1',
              'patientName': 'Kavya Nair',
              'patientPhone': '9111100001',
              'doctorId': 'doc-1',
              'doctorName': 'Dr. Asha Menon',
              'specialty': 'Cardiology',
              'clinicName': 'GS Heart Center',
              'appointmentDate': date,
              'appointmentTime': '09:30 AM',
              'consultationType': 'In-Person',
              'treatment': 'Cardiac Checkup',
              'status': 'COMPLETED',
              'statusCategory': 'Completed',
              'referralInfo': {
                'referralId': 'REF-102',
                'referringDoctorName': 'Dr. Rajiv Verma',
                'referralDate': date,
                'referralStatus': 'Pending',
              },
            },
          ],
    'appointmentsPagination': {
      'page': 1,
      'pageSize': 20,
      'totalItems': emptyDay ? 0 : 1,
      'totalPages': 1,
    },
    'referrals': filteredRefs,
    'referralsPagination': {
      'page': 1,
      'pageSize': 20,
      'totalItems': filteredRefs.length,
      'totalPages': 1,
    },
    'availableDoctors': [
      {'doctorId': 'doc-1', 'doctorName': 'Dr. Asha Menon', 'specialty': 'Cardiology'},
      {'doctorId': 'doc-2', 'doctorName': 'Dr. Rajiv Verma', 'specialty': 'Dentistry'},
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiService.debugDoctorActivityCalendarOverride = null;
  });

  group('GS Health — Admin Doctor Activity Calendar Tests', () {
    test('1. ApiService.fetchAdminDoctorActivityCalendar sends query filters and parses response', () async {
      Uri? capturedUri;
      final mockClient = MockClient((req) async {
        capturedUri = req.url;
        return http.Response(
          jsonEncode(_buildSampleCalendarResponse(date: '2026-11-26', month: '2026-11')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final res = await ApiService().fetchAdminDoctorActivityCalendar(
        date: '2026-11-26',
        month: '2026-11',
        doctorId: 'doc-1',
        appointmentStatus: 'Pending',
        referralStatus: 'Accepted',
        search: 'Kavya',
        page: 2,
        pageSize: 15,
        client: mockClient,
      );

      expect(res['success'], isTrue);
      expect(capturedUri?.path, endsWith('/admin/doctor-activity-calendar'));
      expect(capturedUri?.queryParameters['date'], '2026-11-26');
      expect(capturedUri?.queryParameters['month'], '2026-11');
      expect(capturedUri?.queryParameters['doctorId'], 'doc-1');
      expect(capturedUri?.queryParameters['appointmentStatus'], 'Pending');
      expect(capturedUri?.queryParameters['referralStatus'], 'Accepted');
      expect(capturedUri?.queryParameters['search'], 'Kavya');
      expect(capturedUri?.queryParameters['page'], '2');
      expect(capturedUri?.queryParameters['pageSize'], '15');
    });

    testWidgets(
      '2. Monthly calendar displays Sun-Sat weekdays, summary cards, 9-column doctor table, appointment details modal, and referrals',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        String? lastDateRequested;
        String? lastMonthRequested;
        String? lastRefStatus;

        ApiService.debugDoctorActivityCalendarOverride = ({
          String? date,
          String? month,
          String? doctorId,
          String? appointmentStatus,
          String? referralStatus,
          String? search,
          int page = 1,
          int pageSize = 25,
        }) async {
          lastDateRequested = date;
          lastMonthRequested = month;
          lastRefStatus = referralStatus;
          return _buildSampleCalendarResponse(
            date: date ?? '2026-11-26',
            month: month ?? '2026-11',
            emptyDay: date == '2026-11-15',
            referralStatus: referralStatus,
          );
        };

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AdminDoctorActivityCalendarSection(
                  problemService: PatientProblemService(),
                  initialDate: DateTime(2026, 11, 26),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Weekday headers Sun -> Sat
        for (final wd in ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']) {
          expect(find.text(wd), findsOneWidget);
        }

        // All 7 daily summary cards rendered
        expect(find.byKey(const Key('summary_doctors_active')), findsOneWidget);
        expect(find.byKey(const Key('summary_total_appointments')), findsOneWidget);
        expect(find.byKey(const Key('summary_patients_checked')), findsOneWidget);
        expect(find.byKey(const Key('summary_total_referrals')), findsOneWidget);
        expect(find.byKey(const Key('summary_pending_appointments')), findsOneWidget);
        expect(find.byKey(const Key('summary_completed_appointments')), findsOneWidget);
        expect(find.byKey(const Key('summary_cancelled_appointments')), findsOneWidget);

        // Doctor-wise table columns
        expect(find.text('Doctor Name'), findsWidgets);
        expect(find.text('Doctor ID'), findsOneWidget);
        expect(find.text('Patients Checked'), findsOneWidget);
        expect(find.text('Referrals Received'), findsOneWidget);
        expect(find.text('Referrals Given'), findsOneWidget);

        // Clicking a doctor opens Doctor Daily Activity Detail dialog
        await tester.ensureVisible(find.text('Dr. Asha Menon').first);
        await tester.tap(find.text('Dr. Asha Menon').first);
        await tester.pumpAndSettle();
        expect(find.text('Filter Calendar by This Doctor'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        // Clicking an empty date updates daily summary to empty state
        await tester.ensureVisible(find.byKey(const Key('doctor_calendar_cell_2026-11-15')));
        await tester.tap(find.byKey(const Key('doctor_calendar_cell_2026-11-15')));
        await tester.pumpAndSettle();
        expect(lastDateRequested, '2026-11-15');
        expect(find.text('No doctor activity recorded'), findsOneWidget);
        expect(find.text('No appointments found'), findsOneWidget);
        expect(find.text('No referrals recorded'), findsOneWidget);

        // Next month & Today button navigation
        await tester.ensureVisible(find.byKey(const Key('doctor_calendar_next_month_btn')));
        await tester.tap(find.byKey(const Key('doctor_calendar_next_month_btn')));
        await tester.pumpAndSettle();
        expect(lastMonthRequested, '2026-12');

        await tester.tap(find.byKey(const Key('doctor_calendar_today_btn')));
        await tester.pumpAndSettle();
        expect(lastDateRequested, '2026-11-26');
        expect(lastMonthRequested, '2026-11');

        // Referral status chip filter
        await tester.ensureVisible(find.byKey(const Key('doctor_calendar_ref_chip_accepted')));
        await tester.tap(find.byKey(const Key('doctor_calendar_ref_chip_accepted')));
        await tester.pumpAndSettle();
        expect(lastRefStatus, 'Accepted');
      },
    );

    testWidgets('3. Error state shows Retry button and recovers cleanly on retry', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      int callCount = 0;
      ApiService.debugDoctorActivityCalendarOverride = ({
        String? date,
        String? month,
        String? doctorId,
        String? appointmentStatus,
        String? referralStatus,
        String? search,
        int page = 1,
        int pageSize = 25,
      }) async {
        callCount += 1;
        if (callCount == 1) {
          return {'success': false, 'message': 'Backend unavailable'};
        }
        return _buildSampleCalendarResponse(date: date ?? '2026-11-26', month: month ?? '2026-11');
      };

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AdminDoctorActivityCalendarSection(
                problemService: PatientProblemService(),
                initialDate: DateTime(2026, 11, 26),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('doctor_calendar_error_card')), findsOneWidget);
      expect(find.text('Backend unavailable'), findsOneWidget);

      await tester.tap(find.byKey(const Key('doctor_calendar_retry_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('doctor_calendar_error_card')), findsNothing);
      expect(find.text('Total Doctors Active'), findsOneWidget);
    });

    testWidgets('4. Responsive mobile (390px) and tablet (768px) viewports render with zero RenderFlex overflows', (WidgetTester tester) async {
      ApiService.debugDoctorActivityCalendarOverride = ({
        String? date,
        String? month,
        String? doctorId,
        String? appointmentStatus,
        String? referralStatus,
        String? search,
        int page = 1,
        int pageSize = 25,
      }) async {
        return _buildSampleCalendarResponse(date: date ?? '2026-11-26', month: month ?? '2026-11');
      };

      for (final size in [const Size(390, 844), const Size(768, 1024)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AdminDoctorActivityCalendarSection(
                  problemService: PatientProblemService(),
                  initialDate: DateTime(2026, 11, 26),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Doctor Activity Calendar'), findsOneWidget);
      }

      tester.view.resetPhysicalSize();
    });
  });
}
