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
import 'package:dentaguru/features/patient/presentation/screens/talk_to_dentist_now_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/ai_triage_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final service = PatientProblemService();
    await service.clearAllData();
    service.currentPatient.id = 'patient_test_1';
    service.currentPatient.name = 'Riya Sharma';
    service.currentPatient.phone = '9876543210';
    service.currentPatient.city = 'Mumbai';
    service.currentPatient.languages = ['English', 'Hindi', 'Telugu'];
  });

  tearDown(() async {
    final service = PatientProblemService();
    await service.clearAllData();
  });

  testWidgets('Talk to a Dentist Now Screen renders all components matching GS HEALTH reference UI', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TalkToDentistNowScreen(),
        ),
      ),
    );
    await tester.pump();

    // 1. Header elements
    expect(find.byKey(const Key('talk_to_dentist_back_button')), findsOneWidget);
    expect(find.byKey(const Key('talk_to_dentist_matched_languages')), findsOneWidget);
    expect(find.text('Matched by English / Hindi / Telugu'), findsOneWidget);
    expect(find.byKey(const Key('talk_to_dentist_title')), findsOneWidget);
    expect(find.text('Talk to a dentist now'), findsOneWidget);

    // 2. Availability card (0 online by default)
    expect(find.byKey(const Key('talk_to_dentist_availability_card')), findsOneWidget);
    expect(find.text('No dentists online right now'), findsOneWidget);
    expect(find.byKey(const Key('dentist_availability_dot')), findsOneWidget);

    // 3. Patient concern section
    expect(find.byKey(const Key('talk_to_dentist_concern_label')), findsOneWidget);
    expect(find.text("WHAT'S BOTHERING YOU?"), findsOneWidget);
    expect(find.byKey(const Key('talk_to_dentist_concern_input')), findsOneWidget);
    expect(find.text('e.g. Sharp pain in lower left tooth for 3 days'), findsOneWidget);

    // 4. Primary button: Connect me now
    expect(find.byKey(const Key('talk_to_dentist_connect_button')), findsOneWidget);
    expect(find.text('Connect me now'), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);

    // 5. Secondary button: Not sure? Try AI triage first
    expect(find.byKey(const Key('talk_to_dentist_ai_triage_button')), findsOneWidget);
    expect(find.text('Not sure? Try AI triage first'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
  });

  testWidgets('Dynamic language subtitle reflects patient\'s custom profile languages', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final service = PatientProblemService();
    service.currentPatient.languages = ['Tamil', 'Kannada', 'Hindi'];

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TalkToDentistNowScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Matched by Tamil / Kannada / Hindi'), findsOneWidget);
  });

  testWidgets('Availability card dynamically reflects online dentists with green dot', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final service = PatientProblemService();
    service.addTestDoctor(
      DoctorModel(
        id: 'doc_online_1',
        name: 'Dr. Suresh Kumar',
        specialty: 'Periodontist',
        qualification: 'BDS, MDS',
        clinicName: 'GS Implants Studio',
        phone: '9876543210',
        email: 'suresh@example.com',
        status: 'Available',
        verificationStatus: 'VERIFIED',
        nextAvailableSlots: ['10:00 AM'],
        consultationFee: '₹500',
        rating: 4.9,
        reviewCount: 30,
        experienceYears: 12,
        languages: ['English', 'Telugu'],
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TalkToDentistNowScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1 dentist online right now'), findsOneWidget);

    // Add second online dentist
    service.addTestDoctor(
      DoctorModel(
        id: 'doc_online_2',
        name: 'Dr. Neha Patel',
        specialty: 'Orthodontist',
        qualification: 'BDS, MDS',
        clinicName: 'Smile Care',
        phone: '9876543211',
        email: 'neha@example.com',
        status: 'Online',
        verificationStatus: 'VERIFIED',
        nextAvailableSlots: ['11:00 AM'],
        consultationFee: '₹600',
        rating: 4.8,
        reviewCount: 20,
        experienceYears: 8,
        languages: ['English', 'Hindi', 'Gujarati'],
      ),
    );

    service.notifyListeners();
    await tester.pump();

    expect(find.text('2 dentists online right now'), findsOneWidget);
  });

  testWidgets('Validation on empty concern prevents connection and shows warning', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final service = PatientProblemService();
    service.addTestDoctor(
      DoctorModel(
        id: 'doc_online_1',
        name: 'Dr. Suresh Kumar',
        specialty: 'Periodontist',
        qualification: 'BDS',
        clinicName: 'GS Implants',
        phone: '9876543210',
        email: 'suresh@example.com',
        status: 'Available',
        nextAvailableSlots: ['10:00 AM'],
        consultationFee: '₹500',
        rating: 4.9,
        reviewCount: 10,
        experienceYears: 10,
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TalkToDentistNowScreen(),
        ),
      ),
    );
    await tester.pump();

    // Tap connect with empty concern
    await tester.tap(find.byKey(const Key('talk_to_dentist_connect_button')));
    await tester.pump();

    expect(find.text('Please describe what\'s bothering you before connecting.'), findsOneWidget);
    expect(service.requests, isEmpty);
  });

  testWidgets('Connect me now matches dentist by language and submits consultation', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final service = PatientProblemService();
    service.currentPatient.languages = ['Telugu'];

    // Doctor 1: speaks Hindi & Marathi
    service.addTestDoctor(
      DoctorModel(
        id: 'doc_hindi',
        name: 'Dr. Riya Sharma',
        specialty: 'Endodontist',
        qualification: 'BDS, MDS',
        clinicName: 'Smile Studio',
        phone: '9876543210',
        email: 'riya@example.com',
        status: 'Available',
        verificationStatus: 'VERIFIED',
        nextAvailableSlots: ['10:00 AM'],
        consultationFee: '₹500',
        rating: 4.7,
        reviewCount: 15,
        experienceYears: 5,
        languages: ['Hindi', 'Marathi'],
      ),
    );

    // Doctor 2: speaks Telugu & English (matches patient's language)
    service.addTestDoctor(
      DoctorModel(
        id: 'doc_telugu',
        name: 'Dr. Sumanth Krishna',
        specialty: 'OMFS Specialist',
        qualification: 'BDS, MDS - OMFS',
        clinicName: 'Hyderabad Maxillofacial Clinic',
        phone: '9876543211',
        email: 'sumanth@example.com',
        status: 'Available',
        verificationStatus: 'VERIFIED',
        nextAvailableSlots: ['11:00 AM'],
        consultationFee: '₹700',
        rating: 4.9,
        reviewCount: 50,
        experienceYears: 14,
        languages: ['Telugu', 'English'],
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TalkToDentistNowScreen(),
        ),
      ),
    );
    await tester.pump();

    // Enter concern
    await tester.enterText(
      find.byKey(const Key('talk_to_dentist_concern_input')),
      'Severe wisdom tooth pain radiating to jaw for 2 days',
    );
    await tester.pump();

    // Tap Connect
    await tester.tap(find.byKey(const Key('talk_to_dentist_connect_button')));
    await tester.pump(); // Start submission
    await tester.pump(const Duration(milliseconds: 500)); // Finish async submit

    // Verified matched with Telugu speaking Dr. Sumanth Krishna
    expect(find.text('Matched & Connected!'), findsOneWidget);
    expect(find.textContaining('Dr. Sumanth Krishna'), findsOneWidget);
    expect(find.textContaining('Languages: Telugu, English'), findsOneWidget);

    // Verify consultation request in service
    expect(service.requests.isNotEmpty, isTrue);
    final req = service.requests.first;
    expect(req.preferredDoctorId, equals('doc_telugu'));
    expect(req.preferredDoctorName, equals('Dr. Sumanth Krishna'));
    expect(req.problemDescription, equals('Severe wisdom tooth pain radiating to jaw for 2 days'));

    // Tap Back to Dashboard button in dialog
    await tester.tap(find.byKey(const Key('talk_to_dentist_dialog_done_button')));
    await tester.pump();
  });

  testWidgets('Secondary button navigates to AI Triage Screen and back button returns', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TalkToDentistNowScreen(),
        ),
      ),
    );
    await tester.pump();

    // Type concern
    await tester.enterText(
      find.byKey(const Key('talk_to_dentist_concern_input')),
      'Sharp sensitivity when drinking cold water',
    );
    await tester.pump();

    // Tap "Not sure? Try AI triage first"
    await tester.tap(find.byKey(const Key('talk_to_dentist_ai_triage_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // AI Triage screen should be open
    expect(find.byType(AiTriageScreen), findsOneWidget);
    expect(find.text('AI Dental Triage'), findsOneWidget);
    expect(find.text('Sharp sensitivity when drinking cold water'), findsOneWidget);

    // Let any pending timer complete
    await tester.pump(const Duration(milliseconds: 400));

    // Tap AI triage back button
    await tester.tap(find.byKey(const Key('ai_triage_back_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Back on Talk to Dentist Now screen
    expect(find.byType(TalkToDentistNowScreen), findsOneWidget);
    expect(find.text('Talk to a dentist now'), findsOneWidget);
  });

  testWidgets('No dentists online dialog opens when 0 dentists are online', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TalkToDentistNowScreen(),
        ),
      ),
    );
    await tester.pump();

    // Type concern
    await tester.enterText(
      find.byKey(const Key('talk_to_dentist_concern_input')),
      'Need root canal consultation',
    );
    await tester.pump();

    // Tap connect
    await tester.tap(find.byKey(const Key('talk_to_dentist_connect_button')));
    await tester.pump();

    expect(find.text('No Dentists Online'), findsOneWidget);
    expect(find.byKey(const Key('talk_to_dentist_no_dentists_ai_button')), findsOneWidget);
    expect(find.byKey(const Key('talk_to_dentist_no_dentists_queue_button')), findsOneWidget);
  });

  testWidgets('Navigation from Patient Dashboard opens Talk to a Dentist Now Screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PatientDashboardScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Tap "Talk to a dentist now" card
    final cardFinder = find.byKey(const Key('talk_to_dentist_now_card'));
    expect(cardFinder, findsOneWidget);

    await tester.tap(cardFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify TalkToDentistNowScreen opens
    expect(find.byType(TalkToDentistNowScreen), findsOneWidget);
    expect(find.text('Talk to a dentist now'), findsOneWidget);

    // Tap back button
    await tester.tap(find.byKey(const Key('talk_to_dentist_back_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Back to Patient Dashboard
    expect(find.byType(PatientDashboardScreen), findsOneWidget);
  });

  testWidgets('Responsive layout verification on multiple viewports without RenderFlex overflow', (tester) async {
    final viewports = [
      const Size(320, 640),
      const Size(360, 740),
      const Size(390, 844),
      const Size(412, 915),
    ];

    for (final size in viewports) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: TalkToDentistNowScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('talk_to_dentist_title')), findsOneWidget);
      expect(find.byKey(const Key('talk_to_dentist_connect_button')), findsOneWidget);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('Capture Talk to a Dentist Now Screen visual screenshot', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final service = PatientProblemService();
    service.addTestDoctor(
      DoctorModel(
        id: 'doc_1',
        name: 'Dr. Sumanth Krishna',
        specialty: 'OMFS Specialist',
        qualification: 'BDS, MDS',
        clinicName: 'GS Implants Studio',
        phone: '9876543210',
        email: 'sumanth@example.com',
        status: 'Available',
        verificationStatus: 'VERIFIED',
        nextAvailableSlots: ['10:00 AM'],
        consultationFee: '₹600',
        rating: 4.9,
        reviewCount: 38,
        experienceYears: 12,
        languages: ['English', 'Telugu', 'Hindi'],
      ),
    );

    final repaintBoundaryKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: repaintBoundaryKey,
            child: const TalkToDentistNowScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    // Type sample concern into the field to showcase the UI in its best state
    await tester.enterText(
      find.byKey(const Key('talk_to_dentist_concern_input')),
      'Sharp pain in lower left tooth for 3 days',
    );
    await tester.pump();

    await _capturePngIfPossible(
      tester,
      repaintBoundaryKey,
      r'C:\Users\ADMIN\.gemini\antigravity\brain\0cdf62c7-364d-4c39-8424-4bae41245b5b\gs_health_talk_to_dentist_now.png',
    );
  });
}
