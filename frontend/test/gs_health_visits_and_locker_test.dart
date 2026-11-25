import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';

Future<void> _loadRealFontsIfAvailable() async {
  try {
    final regularFile = File(r'C:\Windows\Fonts\segoeui.ttf');
    final boldFile = File(r'C:\Windows\Fonts\segoeuib.ttf');
    final semiboldFile = File(r'C:\Windows\Fonts\seguisb.ttf');
    if (regularFile.existsSync()) {
      final regBytes = regularFile.readAsBytesSync();
      final boldBytes =
          boldFile.existsSync() ? boldFile.readAsBytesSync() : regBytes;
      final semiBytes =
          semiboldFile.existsSync() ? semiboldFile.readAsBytesSync() : boldBytes;

      for (final family in ['Roboto', 'Plus Jakarta Sans', 'Outfit']) {
        final loader = FontLoader(family)
          ..addFont(
            Future.value(ByteData.view(Uint8List.fromList(regBytes).buffer)),
          )
          ..addFont(
            Future.value(ByteData.view(Uint8List.fromList(semiBytes).buffer)),
          )
          ..addFont(
            Future.value(ByteData.view(Uint8List.fromList(boldBytes).buffer)),
          );
        await loader.load();
      }
    }

    final symbolFile = File(r'C:\Windows\Fonts\seguisym.ttf');
    if (symbolFile.existsSync()) {
      final symBytes = symbolFile.readAsBytesSync();
      final symLoader = FontLoader('Segoe UI Symbol')
        ..addFont(
          Future.value(ByteData.view(Uint8List.fromList(symBytes).buffer)),
        );
      await symLoader.load();
    }

    // Load MaterialIcons font from Flutter SDK cache if available
    final envPath = Platform.environment['PATH'] ?? '';
    for (final dir in envPath.split(';')) {
      if (dir.toLowerCase().contains('flutter')) {
        final sdkRoot = Directory(dir).parent.path;
        final iconFontFile = File(
          '$sdkRoot\\bin\\cache\\artifacts\\material_fonts\\MaterialIcons-Regular.otf',
        );
        if (iconFontFile.existsSync()) {
          final iconBytes = iconFontFile.readAsBytesSync();
          final iconLoader = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(ByteData.view(Uint8List.fromList(iconBytes).buffer)),
            );
          await iconLoader.load();
          break;
        }
      }
    }
  } catch (_) {}
}

Future<void> _capturePngIfPossible(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String outputPath,
) async {
  await tester.runAsync(() async {
    try {
      final boundary =
          boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final file = File(outputPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());
    } catch (_) {
      // Ignore screenshot file write issues in CI environments
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const String artifactDir =
      r'C:\Users\ADMIN\.gemini\antigravity\brain\0cdf62c7-364d-4c39-8424-4bae41245b5b';

  setUpAll(() async {
    await _loadRealFontsIfAvailable();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PatientProblemService().clearAllData();
  });

  void seedVisitsAndLockerData(PatientProblemService service) {
    service.currentPatient = PatientProfile(
      id: 'pat-gs-1',
      name: 'Anu',
      phone: '9876543210',
      age: '28',
      gender: 'Female',
      pincode: '400050',
      photoBytes: Uint8List.fromList(const [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]),
    );

    service.addTestDoctor(
      DoctorModel(
        id: 'doc-ananya',
        userId: 'usr-ananya',
        name: 'Dr. Ananya Rao',
        specialty: 'Endodontist',
        qualification: 'BDS, MDS',
        experienceYears: 9,
        rating: 4.9,
        reviewCount: 48,
        clinicName: 'Bandra West Dental Clinic',
        clinicAddress: 'Bandra West, Mumbai',
        phone: '9820011223',
        email: 'ananya@gshealth.in',
        status: 'Available',
        nextAvailableSlots: ['11:00 AM', '03:00 PM'],
        consultationFee: '600',
      ),
    );

    // Upcoming Visit 1 (Pending, In-clinic, with note)
    service.addTestRequest(
      PatientConsultationRequest(
        id: 'visit-upcoming-1',
        patientId: 'pat-gs-1',
        patientName: 'Anu',
        patientPhone: '9876543210',
        problemCategory: 'Endodontist',
        problemDescription: 'TEST_mode_in_clinic',
        severity: 'Moderate',
        submittedAt: DateTime(2026, 8, 18, 11, 0),
        status: 'PENDING_DOCTOR',
        assignedDoctorId: 'doc-ananya',
        assignedDoctorName: 'Dr. Ananya Rao',
        assignedDoctorSpecialty: 'Endodontist',
        assignedDoctorClinic: 'Bandra West Dental Clinic',
        confirmedDate: '2026-08-18',
        confirmedTimeSlot: '11:00 AM',
      ),
    );

    // Upcoming Visit 2 (Confirmed, In-clinic)
    service.addTestRequest(
      PatientConsultationRequest(
        id: 'visit-upcoming-2',
        patientId: 'pat-gs-1',
        patientName: 'Anu',
        patientPhone: '9876543210',
        problemCategory: 'Endodontist',
        problemDescription: 'TEST_mode_in_clinic',
        severity: 'Mild',
        submittedAt: DateTime(2026, 9, 24, 11, 0),
        status: 'CONFIRMED',
        assignedDoctorId: 'doc-ananya',
        assignedDoctorName: 'Dr. Ananya Rao',
        assignedDoctorSpecialty: 'Endodontist',
        assignedDoctorClinic: 'Bandra West Dental Clinic',
        confirmedDate: '2026-09-24',
        confirmedTimeSlot: '11:00 AM',
      ),
    );

    // Past Visit (Completed, with clinical tooth evaluation)
    service.addTestRequest(
      PatientConsultationRequest(
        id: 'visit-past-rx-1',
        patientId: 'pat-gs-1',
        patientName: 'Anu',
        patientPhone: '9876543210',
        problemCategory: 'Wisdom Tooth Evaluation (#48)',
        problemDescription:
            'Pericoronal flap inflammation around lower right third molar (#48).',
        severity: 'Moderate',
        submittedAt: DateTime(2026, 10, 20, 15, 0),
        status: 'COMPLETED',
        assignedDoctorId: 'doc-ananya',
        assignedDoctorName: 'Dr. Ananya Rao',
        assignedDoctorSpecialty: 'Endodontist',
        assignedDoctorClinic: 'Bandra West Dental Clinic',
        confirmedDate: '2026-10-20',
        confirmedTimeSlot: '03:00 PM',
      ),
    );

    // Issued E-Prescription record in Health Locker
    service.addMedicalRecord({
      'id': 'rx-record-1',
      'patientId': 'pat-gs-1',
      'patientName': 'Anu',
      'type': 'prescription',
      'category': 'Prescription',
      'title': 'Likely pericoronitis around lower right wisdom tooth',
      'diagnosis': 'Likely pericoronitis around lower right wisdom tooth',
      'doctorName': 'Dr. Ananya Rao',
      'clinicName': 'Bandra West Dental Clinic',
      'date': '2026-10-20',
      'items': [
        {
          'name': 'Ibuprofen',
          'dosage': '400mg',
          'frequency': '1-0-1',
          'duration': '3 days',
        },
      ],
      'instructions': 'Warm salt rinses; visit within 3 days',
    });
  }

  group('GS HEALTH My Visits & Health Locker Redesign Verification', () {
    testWidgets(
      '1. My Visits displays Upcoming and Past & cancelled tabs, appointment cards, and supports cancellation',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        seedVisitsAndLockerData(service);

        final boundaryKey = GlobalKey();

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto', useMaterial3: false),
              home: RepaintBoundary(
                key: boundaryKey,
                child: const PatientDashboardScreen(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Tap "Visits" in bottom navigation bar
        final visitsNav = find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Visits'),
        );
        expect(visitsNav, findsOneWidget);
        await tester.tap(visitsNav);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify My visits header and tabs
        expect(find.text('My visits'), findsOneWidget);
        expect(find.text('Upcoming'), findsOneWidget);
        expect(find.text('Past & cancelled'), findsOneWidget);

        // Verify Upcoming appointment card details
        expect(find.text('Dr. Ananya Rao'), findsWidgets);
        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('Confirmed'), findsOneWidget);
        expect(find.text('11:00'), findsWidgets);
        expect(find.text('Bandra West Dental Clinic'), findsWidgets);
        expect(find.text('IN-CLINIC'), findsWidgets);
        expect(find.text('“TEST_mode_in_clinic”'), findsWidgets);
        expect(find.text('Cancel visit'), findsNWidgets(2));

        // Capture My Visits screenshot
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_my_visits.png',
        );

        // Cancel the first upcoming visit
        final cancelBtnFinder =
            find.byKey(const Key('cancel_visit_button_visit-upcoming-1'));
        await tester.ensureVisible(cancelBtnFinder);
        await tester.pump();
        await tester.tap(cancelBtnFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Confirmation dialog appears
        expect(find.text('Cancel visit?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('confirm_cancel_visit_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // Only 1 upcoming visit remains
        expect(find.text('Cancel visit'), findsOneWidget);

        // Switch to "Past & cancelled" tab
        final pastTabFinder = find.byKey(const Key('visits_tab_past_cancelled'));
        await tester.ensureVisible(pastTabFinder);
        await tester.pump();
        await tester.tap(pastTabFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify Completed and Cancelled badges appear, and no Cancel visit button is shown
        expect(find.text('Completed'), findsOneWidget);
        expect(find.text('Cancelled'), findsOneWidget);
        expect(find.text('Cancel visit'), findsNothing);
      },
    );

    testWidgets(
      '2. Health Locker displays Prescriptions, My teeth, and X-rays & reports tabs with expandable e-prescriptions',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        seedVisitsAndLockerData(service);

        // Also add an X-ray document and a Tooth treatment document
        service.addMedicalRecord({
          'id': 'xray-record-1',
          'patientId': 'pat-gs-1',
          'patientName': 'Anu',
          'type': 'xray',
          'category': 'Dental X-ray',
          'title': 'OPG Full Mouth X-Ray',
          'description': 'Bilateral mandibular third molar panoramic view',
          'date': '2026-10-19',
          'fileName': 'opg_scan.pdf',
          'fileType': 'PDF',
          'fileSize': 245760,
          'isPatientUpload': true,
        });
        service.addMedicalRecord({
          'id': 'tooth-record-1',
          'patientId': 'pat-gs-1',
          'patientName': 'Anu',
          'type': 'treatment',
          'category': 'Treatment Documents',
          'title': 'Tooth #48 Clinical Chart',
          'description': 'Operculectomy & irrigation treatment notes',
          'date': '2026-10-20',
          'fileName': 'tooth_48_chart.pdf',
          'fileType': 'PDF',
          'fileSize': 102400,
          'isPatientUpload': true,
        });

        final boundaryKey = GlobalKey();

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto', useMaterial3: false),
              home: RepaintBoundary(
                key: boundaryKey,
                child: const PatientDashboardScreen(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Tap "Locker" in bottom navigation bar
        final lockerNav = find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Locker'),
        );
        expect(lockerNav, findsOneWidget);
        await tester.tap(lockerNav);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify Health Locker header and category tabs
        expect(find.text('Your medical & health records'), findsOneWidget);
        expect(find.text('Health locker'), findsOneWidget);
        expect(find.text('Prescriptions'), findsOneWidget);
        expect(find.text('(1)'), findsOneWidget);
        expect(find.text('Health Records'), findsOneWidget);
        expect(find.text('X-rays & reports'), findsOneWidget);

        // Verify Prescriptions tab expanded card content
        expect(
          find.text('Likely pericoronitis around lower right wisdom tooth'),
          findsOneWidget,
        );
        expect(find.textContaining('Dr. Ananya Rao'), findsOneWidget);
        expect(find.text('E-PRESCRIPTION'), findsOneWidget);
        expect(find.text(' · 1 MEDICINE(S)'), findsOneWidget);
        expect(find.text('℞ Ibuprofen 400mg'), findsOneWidget);
        expect(find.text('1-0-1 · 3 days'), findsOneWidget);
        expect(find.text('Warm salt rinses; visit within 3 days'), findsOneWidget);
        expect(find.text('Bandra West Dental Clinic'), findsOneWidget);

        // Capture Health Locker - Prescriptions screenshot
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_locker_prescriptions.png',
        );

        // Collapse and re-expand the prescription card
        await tester.tap(
          find.text('Likely pericoronitis around lower right wisdom tooth'),
        );
        await tester.pump();
        expect(find.text('E-PRESCRIPTION'), findsNothing);

        await tester.tap(
          find.text('Likely pericoronitis around lower right wisdom tooth'),
        );
        await tester.pump();
        expect(find.text('E-PRESCRIPTION'), findsOneWidget);

        // Switch to "Health Records" tab
        final myTeethTab = find.byKey(const Key('locker_tab_my_teeth'));
        await tester.ensureVisible(myTeethTab);
        await tester.pump();
        await tester.tap(myTeethTab);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Tooth #48 Clinical Chart'), findsOneWidget);
        expect(find.text('Wisdom Tooth Evaluation (#48)'), findsOneWidget);

        // Capture Health Locker - Health Records screenshot
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_locker_my_teeth.png',
        );
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_locker_health_records.png',
        );

        // Switch to "X-rays & reports" tab
        final xraysTab = find.byKey(const Key('locker_tab_xrays_reports'));
        await tester.ensureVisible(xraysTab);
        await tester.pump();
        await tester.tap(xraysTab);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('OPG Full Mouth X-Ray'), findsOneWidget);
        expect(find.text('+ Add Record'), findsOneWidget);
        expect(find.text('View'), findsWidgets);

        // Capture Health Locker - X-rays & reports screenshot
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_locker_xrays_reports.png',
        );
      },
    );

    testWidgets(
      '3. Multi-viewport overflow check (320px, 360px, 390px, 412px) on My Visits and Health Locker',
      (tester) async {
        final service = PatientProblemService();
        seedVisitsAndLockerData(service);

        const widths = [320.0, 360.0, 390.0, 412.0];
        for (final width in widths) {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                key: ValueKey('app_$width'),
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'Roboto', useMaterial3: false),
                home: PatientDashboardScreen(key: ValueKey('dash_$width')),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          // Navigate to Visits
          await tester.tap(
            find.descendant(
              of: find.byType(BottomNavigationBar),
              matching: find.text('Visits'),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull, reason: 'Visits overflow at ${width}px');

          // Navigate to Locker
          await tester.tap(
            find.descendant(
              of: find.byType(BottomNavigationBar),
              matching: find.text('Locker'),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            tester.takeException(),
            isNull,
            reason: 'Locker Prescriptions overflow at ${width}px',
          );

          // Switch to My teeth
          final myTeethTab = find.byKey(const Key('locker_tab_my_teeth'));
          await tester.ensureVisible(myTeethTab);
          await tester.pump();
          await tester.tap(myTeethTab);
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Locker My teeth overflow at ${width}px',
          );

          // Switch to X-rays & reports
          final xraysTab = find.byKey(const Key('locker_tab_xrays_reports'));
          await tester.ensureVisible(xraysTab);
          await tester.pump();
          await tester.tap(xraysTab);
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Locker X-rays overflow at ${width}px',
          );
        }

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
  });
}
