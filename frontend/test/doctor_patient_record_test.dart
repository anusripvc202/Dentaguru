import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:dentaguru/features/dentist/presentation/screens/doctor_patient_record_screen.dart';

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
    } catch (_) {}
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const artifactDir =
      r'C:\Users\ADMIN\.gemini\antigravity\brain\0cdf62c7-364d-4c39-8424-4bae41245b5b';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final service = PatientProblemService();
    await service.clearAllData();

    // Setup doctor
    service.addTestDoctor(
      DoctorModel(
        id: 'doc_sameer_1',
        name: 'Dr. Sameer Khan',
        specialty: 'Orthodontics',
        qualification: 'BDS, MDS',
        experienceYears: 12,
        rating: 4.9,
        reviewCount: 42,
        clinicName: 'GS HEALTH Dental Clinic',
        email: 'doctor@gshealth.com',
        phone: '9876543210',
        status: 'Available',
        nextAvailableSlots: const ['10:00 AM'],
        consultationFee: '₹500',
        languages: const ['English', 'Hindi'],
      ),
    );
    service.currentDoctor = service.allDoctors.first;

    // Setup patients
    final patientRiya = PatientProfile(
      id: 'pat_riya_1',
      name: 'Riya Sharma',
      phone: '9000000200',
      city: 'Mumbai',
      languages: ['English', 'Hindi'],
      age: '28',
      gender: 'Female',
    );
    final patientAarav = PatientProfile(
      id: 'pat_aarav_2',
      name: 'Aarav Patel',
      phone: '9111122233',
      city: 'Pune',
      languages: ['English', 'Marathi'],
      age: '32',
      gender: 'Male',
    );
    service.addTestPatient(patientRiya);
    service.addTestPatient(patientAarav);

    // Setup consultation requests / visits for Riya (2 visits, Fri 13 Nov)
    final req1 = PatientConsultationRequest(
      id: 'req_riya_1',
      patientId: 'pat_riya_1',
      patientName: 'Riya Sharma',
      patientPhone: '9000000200',
      problemCategory: 'Routine Dental Checkup',
      problemDescription: 'Tooth scaling and general dental checkup',
      symptoms: 'Mild sensitivity',
      preferredLocation: 'Mumbai',
      attachments: [],
      severity: 'Mild',
      submittedAt: DateTime(2026, 11, 13, 10, 30),
      confirmedDate: '2026-11-13',
      confirmedTimeSlot: '10:30 AM',
      status: 'COMPLETED',
      assignedDoctorId: service.currentDoctor?.id,
      assignedDoctorName: service.currentDoctor?.name,
      city: 'Mumbai',
      state: 'Maharashtra',
    );
    final req2 = PatientConsultationRequest(
      id: 'req_riya_2',
      patientId: 'pat_riya_1',
      patientName: 'Riya Sharma',
      patientPhone: '9000000200',
      problemCategory: 'Teeth Whitening',
      problemDescription: 'Follow-up consultation',
      symptoms: 'None',
      preferredLocation: 'Mumbai',
      attachments: [],
      severity: 'Mild',
      submittedAt: DateTime(2026, 11, 6, 11, 0),
      confirmedDate: '2026-11-06',
      confirmedTimeSlot: '11:00 AM',
      status: 'CONFIRMED',
      assignedDoctorId: service.currentDoctor?.id,
      assignedDoctorName: service.currentDoctor?.name,
      city: 'Mumbai',
      state: 'Maharashtra',
    );
    service.addTestRequest(req1);
    service.addTestRequest(req2);

    // Setup treatments/medical records for Riya
    service.addMedicalRecord({
      'id': 'rec_riya_1',
      'patientId': 'pat_riya_1',
      'patientName': 'Riya Sharma',
      'type': 'prescription',
      'title': 'Digital Prescription Slips',
      'category': 'Prescription',
      'date': '2026-11-13',
      'instructions': 'Amoxicillin 500mg, 1 Capsule twice daily',
    });
  });

  tearDown(() async {
    final service = PatientProblemService();
    await service.clearAllData();
  });

  testWidgets('My Patients listing renders header, search bar, and patient cards matching Screenshot 1',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RepaintBoundary(
            key: boundaryKey,
            child: const DentistTimelineScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Switch to Patients tab (tab index 1) and allow AnimatedSwitcher transition to complete
    final patientsTabIcon = find.byIcon(Icons.people_outline_rounded);
    expect(patientsTabIcon, findsOneWidget);
    await tester.tap(patientsTabIcon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    // 1. Verify Header
    expect(find.text("Everyone you've cared for"), findsOneWidget);
    expect(find.text('My patients'), findsOneWidget);

    // 2. Verify Search Bar
    expect(find.byKey(const Key('doctor_patients_search_field')), findsOneWidget);
    expect(find.text('Search by name or phone number'), findsOneWidget);

    // 3. Verify Patient Card for Riya Sharma
    expect(find.text('Riya Sharma'), findsOneWidget);
    expect(find.text('+91 9000000200 · Mumbai'), findsOneWidget);
    expect(find.text('2 visits · last Fri, 13 Nov'), findsOneWidget);

    // 4. Verify Aarav Patel is also present
    expect(find.text('Aarav Patel'), findsOneWidget);

    // 5. Test Search Filtering
    await tester.enterText(
        find.byKey(const Key('doctor_patients_search_field')), 'Riya');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Riya Sharma'), findsOneWidget);
    expect(find.text('Aarav Patel'), findsNothing);

    // Clear search
    await tester.enterText(
        find.byKey(const Key('doctor_patients_search_field')), '');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Aarav Patel'), findsOneWidget);

    // Search by phone
    await tester.enterText(
        find.byKey(const Key('doctor_patients_search_field')), '9111122233');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Aarav Patel'), findsOneWidget);
    expect(find.text('Riya Sharma'), findsNothing);

    // Reset search
    await tester.enterText(
        find.byKey(const Key('doctor_patients_search_field')), '');
    await tester.pump(const Duration(milliseconds: 300));

    // Capture visual screenshot of My Patients listing
    await _capturePngIfPossible(
      tester,
      boundaryKey,
      '$artifactDir/gs_health_doctor_my_patients.png',
    );
  });

  testWidgets('Doctor Patient Record Screen renders header, 4 stats, action buttons, and tabs matching Screenshot 2',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final patient = PatientProfile(
      id: 'pat_riya_1',
      name: 'Riya Sharma',
      phone: '9000000200',
      city: 'Mumbai',
      languages: ['English', 'Hindi'],
      age: '28',
      gender: 'Female',
    );

    final boundaryKey = GlobalKey();
    bool referCalled = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RepaintBoundary(
            key: boundaryKey,
            child: DoctorPatientRecordScreen(
              patient: patient,
              visitsCountOverride: 28,
              completedCountOverride: 1,
              treatmentsCountOverride: 1,
              consultsCountOverride: 1,
              onRefer: () => referCalled = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Header verification
    expect(find.byKey(const Key('patient_record_back_button')), findsOneWidget);
    expect(find.text('Patient record'), findsOneWidget);
    expect(find.text('Riya Sharma'), findsNWidgets(2)); // in header + in info card

    // 2. Patient info card verification
    expect(find.text('+91 9000000200'), findsOneWidget);
    expect(find.text('Mumbai'), findsOneWidget);
    expect(find.text('English, Hindi'), findsOneWidget);

    // 3. 4 Stat cards in a row
    expect(find.byKey(const Key('stat_visits')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('stat_visits')),
            matching: find.text('28')),
        findsOneWidget);
    expect(find.text('Visits'), findsOneWidget);

    expect(find.byKey(const Key('stat_completed')), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);

    expect(find.byKey(const Key('stat_treatments')), findsOneWidget);
    expect(find.text('Treatments'), findsOneWidget);

    expect(find.byKey(const Key('stat_consults')), findsOneWidget);
    expect(find.text('Consults'), findsOneWidget);

    // 4. Action buttons verification
    expect(find.byKey(const Key('patient_record_write_rx_button')), findsOneWidget);
    expect(find.text('Write Rx'), findsOneWidget);
    expect(find.byKey(const Key('patient_record_refer_button')), findsOneWidget);
    expect(find.text('Refer'), findsOneWidget);

    // Tap Refer button
    await tester.tap(find.byKey(const Key('patient_record_refer_button')));
    await tester.pumpAndSettle();
    expect(referCalled, isTrue);

    // Tap Write Rx button (opens internal prescription modal)
    await tester.tap(find.byKey(const Key('patient_record_write_rx_button')));
    await tester.pumpAndSettle();
    expect(find.text('Issue E-Prescription'), findsOneWidget);
    expect(find.text('Send Digital E-Prescription to Patient'), findsOneWidget);
    // Close prescription modal
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // 5. Tabs verification (Tooth chart & notes is NOT present by default per user request)
    expect(find.byKey(const Key('tab_tooth_chart')), findsNothing);
    expect(find.text('Tooth chart & notes'), findsNothing);
    expect(find.byKey(const Key('tab_visits')), findsOneWidget);
    expect(find.text('Visits (28)'), findsOneWidget);
    expect(find.byKey(const Key('tab_treatments')), findsOneWidget);
    expect(find.text('Treatments (1)'), findsOneWidget);

    // Verify tooth chart container and quadrants are completely absent
    expect(find.byKey(const Key('tooth_chart_container')), findsNothing);
    expect(find.text('Upper right'), findsNothing);
    expect(find.text('Upper left'), findsNothing);
    expect(find.text('Lower left'), findsNothing);
    expect(find.text('Lower right'), findsNothing);

    // Capture visual screenshot of Patient Record screen without tooth chart
    await _capturePngIfPossible(
      tester,
      boundaryKey,
      '$artifactDir/gs_health_doctor_patient_record.png',
    );
  });

  testWidgets('Tooth Chart renders 4 quadrants (18-11, 21-28, 31-38, 48-41) when showToothChart is true',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final patient = PatientProfile(
      id: 'pat_riya_1',
      name: 'Riya Sharma',
      phone: '9000000200',
      city: 'Mumbai',
      languages: ['English', 'Hindi'],
    );

    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RepaintBoundary(
            key: boundaryKey,
            child: DoctorPatientRecordScreen(
              patient: patient,
              visitsCountOverride: 28,
              completedCountOverride: 1,
              treatmentsCountOverride: 1,
              consultsCountOverride: 1,
              showToothChart: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Quadrants verification
    expect(find.text('Upper right'), findsOneWidget);
    for (final t in [18, 17, 16, 15, 14, 13, 12, 11]) {
      expect(
          find.descendant(
              of: find.byKey(const Key('tooth_chart_container')),
              matching: find.text('$t')),
          findsOneWidget);
    }

    expect(find.text('Upper left'), findsOneWidget);
    for (final t in [21, 22, 23, 24, 25, 26, 27, 28]) {
      expect(
          find.descendant(
              of: find.byKey(const Key('tooth_chart_container')),
              matching: find.text('$t')),
          findsOneWidget);
    }

    expect(find.text('Lower left'), findsOneWidget);
    for (final t in [31, 32, 33, 34, 35, 36, 37, 38]) {
      expect(
          find.descendant(
              of: find.byKey(const Key('tooth_chart_container')),
              matching: find.text('$t')),
          findsOneWidget);
    }

    expect(find.text('Lower right'), findsOneWidget);
    for (final t in [48, 47, 46, 45, 44, 43, 42, 41]) {
      expect(
          find.descendant(
              of: find.byKey(const Key('tooth_chart_container')),
              matching: find.text('$t')),
          findsOneWidget);
    }

    // 2. Status legend (Planned indicator)
    expect(find.text('Planned'), findsOneWidget);

    // 3. CRITICAL RESTRICTION: "Add treatment note" button MUST NOT be present!
    expect(find.text('Add treatment note'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Add treatment note'), findsNothing);

    // 4. Empty state verification
    expect(find.text('No treatment notes yet'), findsOneWidget);
    expect(find.text('Add a note after each visit to build the tooth chart.'), findsOneWidget);

    // Capture visual screenshot of Patient Record screen with optional tooth chart
    await _capturePngIfPossible(
      tester,
      boundaryKey,
      '$artifactDir/gs_health_doctor_tooth_chart_optional.png',
    );
  });

  testWidgets('Doctor Patient Record Screen tab switching (Visits & Treatments)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final patient = PatientProfile(
      id: 'pat_riya_1',
      name: 'Riya Sharma',
      phone: '9000000200',
      city: 'Mumbai',
      languages: ['English', 'Hindi'],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DoctorPatientRecordScreen(
            patient: patient,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Initial tab is Visits (since tooth chart is removed by default)
    expect(find.byKey(const Key('tab_tooth_chart')), findsNothing);
    expect(find.byKey(const Key('tooth_chart_tab_content')), findsNothing);
    expect(find.byKey(const Key('patient_visits_list')), findsOneWidget);
    expect(find.text('Routine Dental Checkup'), findsOneWidget);
    expect(find.text('Teeth Whitening'), findsOneWidget);

    // 2. Switch to Treatments tab
    await tester.ensureVisible(find.byKey(const Key('tab_treatments')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('tab_treatments')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('patient_treatments_list')), findsOneWidget);
    expect(find.text('Digital Prescription Slips'), findsOneWidget);

    // 3. Switch back to Visits tab
    await tester.ensureVisible(find.byKey(const Key('tab_visits')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('tab_visits')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('patient_visits_list')), findsOneWidget);
    expect(find.text('Routine Dental Checkup'), findsOneWidget);
  });

  testWidgets('Doctor Patient Record Screen is responsive across 320, 360, 390, 412 width viewports without RenderFlex overflow',
      (tester) async {
    final patient = PatientProfile(
      id: 'pat_riya_1',
      name: 'Riya Sharma',
      phone: '9000000200',
      city: 'Mumbai',
      languages: ['English', 'Hindi'],
    );

    final viewports = [
      const Size(320, 640),
      const Size(360, 780),
      const Size(390, 844),
      const Size(412, 915),
    ];

    for (final size in viewports) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DoctorPatientRecordScreen(
              patient: patient,
              visitsCountOverride: 28,
              completedCountOverride: 1,
              treatmentsCountOverride: 1,
              consultsCountOverride: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'Failed on viewport ${size.width}x${size.height}');
      expect(find.text('Riya Sharma'), findsWidgets);
      expect(find.text('Visits'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Treatments'), findsOneWidget);
      expect(find.text('Consults'), findsOneWidget);
    }
  });
}
