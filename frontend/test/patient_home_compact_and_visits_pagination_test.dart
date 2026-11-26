import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';

final _samplePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionService().clearSession();
    final service = PatientProblemService();
    await service.clearAllData();
    service.currentPatient = PatientProfile(
      id: 'pat-visits-1',
      name: 'Anu',
      phone: '9876543210',
      city: 'Hyderabad',
      age: '29',
      gender: 'Female',
      pincode: '500081',
      photoBytes: _samplePng,
    );
    service.registerDoctor(
      id: 'doc-sri-1',
      userId: 'usr-sri-1',
      name: 'Dr. Sri',
      specialty: 'Cardiology',
      qualification: 'MBBS, MD',
      experienceYears: 10,
      clinicName: 'GS HEALTH Practice',
      phone: '9988776655',
      email: 'sri@gshealth.in',
      licenseNumber: 'MED-LIC-SRI-1',
      consultationFee: '₹700',
    );
  });

  tearDown(() async {
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  void seedMixedVisits(PatientProblemService service) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final dayAfter = now.add(const Duration(days: 2));
    final lastWeek = now.subtract(const Duration(days: 7));
    final twoWeeksAgo = now.subtract(const Duration(days: 14));
    final monthAgo = now.subtract(const Duration(days: 30));

    String isoDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    // 1. Upcoming CONFIRMED (soonest)
    service.addTestRequest(
      PatientConsultationRequest(
        id: 'v-up-soonest',
        patientId: 'pat-visits-1',
        patientName: 'Anu',
        patientPhone: '9876543210',
        problemCategory: 'Cardiology',
        problemDescription: 'Chest pain follow-up',
        preferredLocation: 'GS HEALTH Practice',
        severity: 'Moderate',
        submittedAt: now.subtract(const Duration(hours: 2)),
        confirmedDate: isoDate(tomorrow),
        confirmedTimeSlot: '02:00 PM',
        assignedDoctorId: 'doc-sri-1',
        assignedDoctorName: 'Dr. Sri',
        assignedDoctorSpecialty: 'Cardiology',
        assignedDoctorClinic: 'GS HEALTH Practice',
        status: 'CONFIRMED',
      ),
    );

    // 2. Upcoming RESCHEDULED (later upcoming)
    service.addTestRequest(
      PatientConsultationRequest(
        id: 'v-up-rescheduled',
        patientId: 'pat-visits-1',
        patientName: 'Anu',
        patientPhone: '9876543210',
        problemCategory: 'Cardiology',
        problemDescription: 'ECG review',
        preferredLocation: 'GS HEALTH Practice',
        severity: 'Mild',
        submittedAt: now.subtract(const Duration(hours: 5)),
        confirmedDate: isoDate(dayAfter),
        confirmedTimeSlot: '03:00 PM',
        assignedDoctorId: 'doc-sri-1',
        assignedDoctorName: 'Dr. Sri',
        assignedDoctorSpecialty: 'Cardiology',
        assignedDoctorClinic: 'GS HEALTH Practice',
        status: 'RESCHEDULED',
      ),
    );

    // 3. Recent COMPLETED (3rd item shown by default)
    service.addTestRequest(
      PatientConsultationRequest(
        id: 'v-comp-recent',
        patientId: 'pat-visits-1',
        patientName: 'Anu',
        patientPhone: '9876543210',
        problemCategory: 'Cardiology',
        problemDescription: 'Blood pressure check',
        preferredLocation: 'GS HEALTH Practice',
        severity: 'Mild',
        submittedAt: lastWeek,
        confirmedDate: isoDate(lastWeek),
        confirmedTimeSlot: '11:00 AM',
        assignedDoctorId: 'doc-sri-1',
        assignedDoctorName: 'Dr. Sri',
        assignedDoctorSpecialty: 'Cardiology',
        assignedDoctorClinic: 'GS HEALTH Practice',
        status: 'COMPLETED',
      ),
    );

    // 4. Older COMPLETED (hidden until View All)
    service.addTestRequest(
      PatientConsultationRequest(
        id: 'v-comp-older-1',
        patientId: 'pat-visits-1',
        patientName: 'Anu',
        patientPhone: '9876543210',
        problemCategory: 'General Medicine',
        problemDescription: 'Routine annual checkup',
        preferredLocation: 'GS HEALTH Practice',
        severity: 'Mild',
        submittedAt: twoWeeksAgo,
        confirmedDate: isoDate(twoWeeksAgo),
        confirmedTimeSlot: '10:00 AM',
        assignedDoctorId: 'doc-sri-1',
        assignedDoctorName: 'Dr. Sri',
        assignedDoctorSpecialty: 'Cardiology',
        assignedDoctorClinic: 'GS HEALTH Practice',
        status: 'COMPLETED',
      ),
    );

    // 5. Oldest COMPLETED (hidden until View All)
    service.addTestRequest(
      PatientConsultationRequest(
        id: 'v-comp-older-2',
        patientId: 'pat-visits-1',
        patientName: 'Anu',
        patientPhone: '9876543210',
        problemCategory: 'General Medicine',
        problemDescription: 'Lab report consultation',
        preferredLocation: 'GS HEALTH Practice',
        severity: 'Mild',
        submittedAt: monthAgo,
        confirmedDate: isoDate(monthAgo),
        confirmedTimeSlot: '09:30 AM',
        assignedDoctorId: 'doc-sri-1',
        assignedDoctorName: 'Dr. Sri',
        assignedDoctorSpecialty: 'Cardiology',
        assignedDoctorClinic: 'GS HEALTH Practice',
        status: 'COMPLETED',
      ),
    );

    // Inject duplicate ID to verify deduplication prevents duplicate cards
    service.addTestRequest(
      PatientConsultationRequest(
        id: 'v-up-soonest',
        patientId: 'pat-visits-1',
        patientName: 'Anu',
        patientPhone: '9876543210',
        problemCategory: 'Cardiology',
        problemDescription: 'Duplicate row test',
        preferredLocation: 'GS HEALTH Practice',
        severity: 'Moderate',
        submittedAt: now.subtract(const Duration(hours: 2)),
        confirmedDate: isoDate(tomorrow),
        confirmedTimeSlot: '02:00 PM',
        assignedDoctorId: 'doc-sri-1',
        assignedDoctorName: 'Dr. Sri',
        assignedDoctorSpecialty: 'Cardiology',
        assignedDoctorClinic: 'GS HEALTH Practice',
        status: 'CONFIRMED',
      ),
    );
  }

  group('GS Health Patient Home Compact & Visits Latest-3 / View All', () {
    testWidgets(
      '1-4 & 6. Home hides full Upcoming/Scheduled cards, opens Visits showing latest 3 sorted visits, View All expands all, Show Less returns to 3, zero data deleted',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final service = PatientProblemService();
        seedMixedVisits(service);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: PatientDashboardScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 1. Home page shows compact summary with Open Visits CTA, and NO full Upcoming Consultation / Scheduled Visit cards
        expect(find.byKey(const Key('hero_appointment_title')), findsOneWidget);
        expect(find.byKey(const Key('home_open_visits_button')), findsOneWidget);
        expect(find.text('Upcoming Consultation'), findsNothing);
        expect(find.text('Scheduled Visit'), findsNothing);
        expect(find.byKey(const Key('upcoming_consultation_card_v-up-soonest')), findsNothing);
        expect(find.byKey(const Key('upcoming_consultation_card_v-up-rescheduled')), findsNothing);

        // Need Any Help card on Patient Dashboard shows WhatsApp only (Call Us Now removed)
        expect(find.text('Need Any Help?'), findsOneWidget);
        expect(find.text('Chat on WhatsApp'), findsOneWidget);
        expect(find.text('Call Us Now'), findsNothing);

        // Tap Open Visits from Home compact summary
        await tester.tap(find.byKey(const Key('home_open_visits_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 2. Visits page initially shows ONLY the latest 3 records (upcoming first, then recent completed), deduplicated (5 unique total)
        expect(find.text('My visits'), findsOneWidget);
        expect(find.text('Showing latest 3 of 5 visits'), findsOneWidget);
        expect(find.byKey(const Key('visit_card_v-up-soonest')), findsOneWidget);
        expect(find.byKey(const Key('visit_card_v-up-rescheduled')), findsOneWidget);
        expect(find.byKey(const Key('visit_card_v-comp-recent')), findsOneWidget);
        expect(find.byKey(const Key('visit_card_v-comp-older-1')), findsNothing);
        expect(find.byKey(const Key('visit_card_v-comp-older-2')), findsNothing);

        // Verify sorting order: soonest upcoming is above rescheduled, which is above completed
        final ySoonest = tester.getTopLeft(find.byKey(const Key('visit_card_v-up-soonest'))).dy;
        final yRescheduled = tester.getTopLeft(find.byKey(const Key('visit_card_v-up-rescheduled'))).dy;
        final yCompleted = tester.getTopLeft(find.byKey(const Key('visit_card_v-comp-recent'))).dy;
        expect(ySoonest, lessThan(yRescheduled));
        expect(yRescheduled, lessThan(yCompleted));

        // 3. View All displays ALL 5 unique visit records including older completed visits
        final viewAllHeaderBtn = find.byKey(const Key('visits_view_all_header_button'));
        expect(viewAllHeaderBtn, findsOneWidget);
        await tester.tap(viewAllHeaderBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Showing 5 of 5 visits'), findsOneWidget);

        // Scroll down to verify older visits and Show Less button are rendered
        await tester.scrollUntilVisible(
          find.byKey(const Key('visit_card_v-comp-older-2')),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.byKey(const Key('visit_card_v-comp-older-1')), findsOneWidget);
        expect(find.byKey(const Key('visit_card_v-comp-older-2')), findsOneWidget);

        // 4. Show Less returns to the latest 3 records view
        await tester.scrollUntilVisible(
          find.byKey(const Key('visits_show_less_button')),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.byKey(const Key('visits_show_less_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Showing latest 3 of 5 visits'), findsOneWidget);
        expect(find.byKey(const Key('visit_card_v-comp-older-1')), findsNothing);
        expect(find.byKey(const Key('visit_card_v-comp-older-2')), findsNothing);

        // 6. Verify no existing appointment data was deleted from service
        final storedIds = service.requests.map((r) => r.id).toSet();
        expect(storedIds.containsAll([
          'v-up-soonest',
          'v-up-rescheduled',
          'v-comp-recent',
          'v-comp-older-1',
          'v-comp-older-2',
        ]), isTrue);
      },
    );

    testWidgets(
      '5. Chat, Details, and Reschedule actions work cleanly from Visit cards in Visits tab',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final service = PatientProblemService();
        seedMixedVisits(service);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: PatientDashboardScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Open Visits tab
        await tester.tap(find.byKey(const Key('home_open_visits_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify Chat, Details, and Reschedule buttons exist on upcoming visit card
        final chatBtn = find.byKey(const Key('chat_visit_button_v-up-soonest'));
        final detailsBtn = find.byKey(const Key('details_visit_button_v-up-soonest'));
        final rescheduleBtn = find.byKey(const Key('reschedule_visit_button_v-up-soonest'));
        expect(chatBtn, findsOneWidget);
        expect(detailsBtn, findsOneWidget);
        expect(rescheduleBtn, findsOneWidget);

        // Test Details dialog opens cleanly
        await tester.ensureVisible(detailsBtn);
        await tester.tap(detailsBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Appointment Details'), findsOneWidget);
        // Close Details dialog
        await tester.tap(find.byIcon(Icons.close_rounded).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Test Reschedule dialog opens cleanly
        await tester.ensureVisible(rescheduleBtn);
        await tester.tap(rescheduleBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Reschedule Visit'), findsWidgets);
        await tester.tap(find.byIcon(Icons.close_rounded).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Test Chat modal opens cleanly
        await tester.ensureVisible(chatBtn);
        await tester.tap(chatBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('Dr. Sri'), findsWidgets);
      },
    );

    testWidgets(
      'Large visit history (>20 visits) supports View All + Load More pagination without truncation',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final service = PatientProblemService();
        final now = DateTime.now();
        for (int i = 1; i <= 25; i++) {
          final d = now.subtract(Duration(days: i));
          final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          service.addTestRequest(
            PatientConsultationRequest(
              id: 'v-hist-$i',
              patientId: 'pat-visits-1',
              patientName: 'Anu',
              patientPhone: '9876543210',
              problemCategory: 'Cardiology',
              problemDescription: 'History visit $i',
              preferredLocation: 'GS HEALTH Practice',
              severity: 'Mild',
              submittedAt: d,
              confirmedDate: iso,
              confirmedTimeSlot: '10:00 AM',
              assignedDoctorId: 'doc-sri-1',
              assignedDoctorName: 'Dr. Sri',
              assignedDoctorSpecialty: 'Cardiology',
              assignedDoctorClinic: 'GS HEALTH Practice',
              status: 'COMPLETED',
            ),
          );
        }

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: PatientDashboardScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(
          find.descendant(
            of: find.byType(BottomNavigationBar),
            matching: find.text('Visits'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Initially 3 of 25
        expect(find.text('Showing latest 3 of 25 visits'), findsOneWidget);

        // Tap View All -> loads first page of 20
        await tester.tap(find.byKey(const Key('visits_view_all_header_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Showing 20 of 25 visits'), findsOneWidget);

        // Scroll to Load More button and tap -> loads remaining 5 (all 25 shown)
        await tester.scrollUntilVisible(
          find.byKey(const Key('visits_load_more_button')),
          400,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.byKey(const Key('visits_load_more_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Showing 25 of 25 visits'), findsOneWidget);
      },
    );
  });
}
