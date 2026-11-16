import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadRealFontsIfAvailable() async {
  try {
    final regularFile = File(r'C:\Windows\Fonts\segoeui.ttf');
    final boldFile = File(r'C:\Windows\Fonts\segoeuib.ttf');
    final semiboldFile = File(r'C:\Windows\Fonts\seguisb.ttf');
    if (regularFile.existsSync()) {
      final regBytes = regularFile.readAsBytesSync();
      final boldBytes = boldFile.existsSync() ? boldFile.readAsBytesSync() : regBytes;
      final semiBytes = semiboldFile.existsSync() ? semiboldFile.readAsBytesSync() : boldBytes;

      for (final family in ['Roboto', 'Plus Jakarta Sans', 'Outfit', 'Segoe UI']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.view(Uint8List.fromList(regBytes).buffer)))
          ..addFont(Future.value(ByteData.view(Uint8List.fromList(semiBytes).buffer)))
          ..addFont(Future.value(ByteData.view(Uint8List.fromList(boldBytes).buffer)));
        await loader.load();
      }
    }

    final symbolFile = File(r'C:\Windows\Fonts\seguisym.ttf');
    if (symbolFile.existsSync()) {
      final symBytes = symbolFile.readAsBytesSync();
      final symLoader = FontLoader('Segoe UI Symbol')
        ..addFont(Future.value(ByteData.view(Uint8List.fromList(symBytes).buffer)));
      await symLoader.load();
    }
  } catch (_) {}
}

Future<void> _capturePngIfPossible(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String outputPath,
) async {
  for (final element in find.byType(Image).evaluate()) {
    final widget = element.widget as Image;
    await tester.runAsync(() async {
      try {
        await precacheImage(widget.image, element);
      } catch (_) {}
    });
  }
  await tester.pump();
  await tester.runAsync(() async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      await File(outputPath).writeAsBytes(byteData.buffer.asUint8List());
    } catch (_) {}
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const String artifactDir = r'C:\Users\ADMIN\.gemini\antigravity\brain\0cdf62c7-364d-4c39-8424-4bae41245b5b';

  setUpAll(() async {
    await _loadRealFontsIfAvailable();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await PatientProblemService().clearAllDataAndStorage();
  });

  group('GS HEALTH - Referral Payload Sanitization & Access Control Tests', () {
    test('Raw REFERRAL_PAYLOAD JSON is strictly suppressed from admin guidance', () {
      const rawPayload =
          'REFERRAL_PAYLOAD:{"id":"ref-1794652338764","referrer_patient_id":"92a3477e-45f5-48fb-ba31-273e7d9c7adc","referrer_id":"92a3477e-45f5-48fb-ba31-273e7d9c7adc","referred_patient_id":"5dc43c2e-c958-409b-9d5b-8623a3f548c1","referred_user_id":"5dc43c2e-c958-409b-9d5b-8623a3f548c1","referred_patient_name":"suchi","referred_patient_mobile":"9087654387","referred_patient_age":"","referred_patient_gender":"Female","referred_patient_city":"hyd"}';

      final clean = PatientConsultationRequest.sanitizeAdminGuidance(rawPayload);
      expect(clean, isNull);
    });

    test('Meaningful referral instructions inside payload are formatted and displayed', () {
      final payloadWithInstructions =
          'REFERRAL_PAYLOAD:${jsonEncode({'id': 'ref-1794652338764', 'referrer_id': '92a3477e', 'instructions': 'Patient has gag reflex, use topical spray prior to examination.'})}';

      final clean = PatientConsultationRequest.sanitizeAdminGuidance(payloadWithInstructions);
      expect(clean, 'Patient has gag reflex, use topical spray prior to examination.');
      expect(clean!.contains('REFERRAL_PAYLOAD'), isFalse);
      expect(clean.contains('ref-1794652338764'), isFalse);
      expect(clean.contains('92a3477e'), isFalse);
    });

    test('Human admin guidance without JSON payload is preserved as formatted text', () {
      const normalNote = 'Direct referral to Dr. Nikhil (Nikhil clinic)';
      final clean = PatientConsultationRequest.sanitizeAdminGuidance(normalNote);
      expect(clean, 'Direct referral to Dr. Nikhil (Nikhil clinic)');
    });

    test('Pure technical JSON object strings are suppressed', () {
      final technicalJson = jsonEncode({'id': 'internal-uuid-1', 'status': 'PENDING'});
      final clean = PatientConsultationRequest.sanitizeAdminGuidance(technicalJson);
      expect(clean, isNull);
    });

    test('Clean referral reason extraction removes wrapper description and phone', () {
      final req = PatientConsultationRequest(
        id: 'req-1',
        patientName: 'suchi',
        patientPhone: '9087654387',
        problemCategory: 'General Dentistry',
        problemDescription: 'Referral for suchi (9087654387): pain',
        severity: 'Moderate',
        submittedAt: DateTime.now(),
        adminNotes: 'REFERRAL_PAYLOAD:{"id":"ref-123"}',
      );

      expect(req.isReferral, isTrue);
      expect(req.cleanReferralReason, 'pain');
    });

    test('Patient mobile number access control masks phone when unauthorized and displays when authorized', () {
      final req = PatientConsultationRequest(
        id: 'req-2',
        patientName: 'suchi',
        patientPhone: '9087654387',
        problemCategory: 'General Dentistry',
        problemDescription: 'pain',
        severity: 'Moderate',
        submittedAt: DateTime.now(),
      );

      // Authorized doctor
      final authPhone = req.getFormattedPatientPhone(isAuthorized: true);
      expect(authPhone, '+91 9087654387');

      // Unauthorized user
      final unauthPhone = req.getFormattedPatientPhone(isAuthorized: false);
      expect(unauthPhone, contains('•••••'));
      expect(unauthPhone, contains('387'));
      expect(unauthPhone.contains('9087654387'), isFalse);
    });

    test('Missing phone never falls back to dummy phone', () {
      final req = PatientConsultationRequest(
        id: 'req-3',
        patientName: 'Riya',
        patientPhone: '',
        problemCategory: 'General Dentistry',
        problemDescription: 'checkup',
        severity: 'Moderate',
        submittedAt: DateTime.now(),
      );

      final phone = req.getFormattedPatientPhone(isAuthorized: true);
      expect(phone, 'Phone not provided');
      expect(phone.contains('9000000200'), isFalse);
    });
  });

  group('GS HEALTH - Doctor Dashboard Requests UI Rendering Test', () {
    testWidgets('Doctor Dashboard Requests page renders clean referral without raw JSON or internal IDs', (tester) async {
      final service = PatientProblemService();

      // Configure current doctor
      final doctor = DoctorModel(
        id: 'doc-nikhil-uuid',
        name: 'Dr. Nikhil',
        specialty: 'General Dentistry',
        qualification: 'BDS, MDS',
        experienceYears: 8,
        rating: 4.9,
        reviewCount: 32,
        clinicName: 'Nikhil Dental Studio',
        phone: '+919988776655',
        email: 'nikhil@gshealth.in',
        status: 'Available',
        verificationStatus: 'VERIFIED',
        nextAvailableSlots: const ['10:00 AM', '11:30 AM'],
        consultationFee: '₹500',
      );
      service.currentDoctor = doctor;
      service.addTestDoctor(doctor);

      // Add the referral request matching the user screenshot
      const rawUserPayload =
          'REFERRAL_PAYLOAD:{"id":"ref-1794652338764","referrer_patient_id":"92a3477e-45f5-48fb-ba31-273e7d9c7adc","referrer_id":"92a3477e-45f5-48fb-ba31-273e7d9c7adc","referred_patient_id":"5dc43c2e-c958-409b-9d5b-8623a3f548c1","referred_user_id":"5dc43c2e-c958-409b-9d5b-8623a3f548c1","referred_patient_name":"suchi","referred_patient_mobile":"9087654387","referred_patient_age":"","referred_patient_gender":"Female","referred_patient_city":"hyd"}';

      final referralRequest = PatientConsultationRequest(
        id: 'PR-1794652338764',
        patientName: 'suchi',
        patientPhone: '9087654387',
        problemCategory: 'General Dentistry',
        problemDescription: 'Referral for suchi (9087654387): pain',
        severity: 'Moderate',
        submittedAt: DateTime(2026, 11, 14, 10, 30),
        status: 'DENTIST_ASSIGNED',
        assignedDoctorId: 'doc-nikhil-uuid',
        assignedDoctorName: 'Dr. Nikhil',
        assignedDoctorSpecialty: 'General Dentistry',
        assignedDoctorClinic: 'Nikhil Dental Studio',
        adminNotes: rawUserPayload,
      );

      service.addTestAssignedRequest(referralRequest);

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFFF8FAFC),
              body: RepaintBoundary(
                key: key,
                child: const DentistTimeline(initialTabIndex: 2), // Requests Tab (Index 2)
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Verify Clean Patient & Referral Information
      expect(find.text('suchi · +91 9087654387'), findsOneWidget);
      expect(find.text('Suggested: General Dentistry'), findsOneWidget);
      expect(find.text('Assigned to Dr. Nikhil'), findsOneWidget);
      expect(find.text('Referral Reason: pain'), findsOneWidget);
      expect(find.text('Accept case'), findsOneWidget);

      // 2. CRITICAL VERIFICATION: Raw JSON & Internal IDs MUST NOT EXIST
      expect(find.textContaining('REFERRAL_PAYLOAD'), findsNothing);
      expect(find.textContaining('ref-1794652338764'), findsNothing);
      expect(find.textContaining('92a3477e'), findsNothing);
      expect(find.textContaining('5dc43c2e'), findsNothing);
      expect(find.textContaining('referred_patient_id'), findsNothing);
      expect(find.textContaining('referrer_id'), findsNothing);
      expect(find.text('ADMIN GUIDANCE'), findsNothing);

      // 3. Capture visual artifact
      await _capturePngIfPossible(tester, key, '$artifactDir\\gs_health_doctor_requests_sanitized.png');
    });

    testWidgets('Doctor Dashboard Requests page displays formatted text when instructions are provided', (tester) async {
      final service = PatientProblemService();

      final doctor = DoctorModel(
        id: 'doc-nikhil-uuid',
        name: 'Dr. Nikhil',
        specialty: 'General Dentistry',
        qualification: 'BDS, MDS',
        experienceYears: 8,
        rating: 4.9,
        reviewCount: 32,
        clinicName: 'Nikhil Dental Studio',
        phone: '+919988776655',
        email: 'nikhil@gshealth.in',
        status: 'Available',
        verificationStatus: 'VERIFIED',
        nextAvailableSlots: const ['10:00 AM'],
        consultationFee: '₹500',
      );
      service.currentDoctor = doctor;
      service.addTestDoctor(doctor);

      final payloadWithInstructions =
          'REFERRAL_PAYLOAD:${jsonEncode({'id': 'ref-999', 'instructions': 'Patient has mild dental anxiety. Pre-consultation reassuring call recommended.'})}';

      final referralRequest = PatientConsultationRequest(
        id: 'PR-999',
        patientName: 'suchi',
        patientPhone: '9087654387',
        problemCategory: 'General Dentistry',
        problemDescription: 'Referral for suchi (9087654387): pain',
        severity: 'Moderate',
        submittedAt: DateTime(2026, 11, 14, 10, 30),
        status: 'DENTIST_ASSIGNED',
        assignedDoctorId: 'doc-nikhil-uuid',
        assignedDoctorName: 'Dr. Nikhil',
        assignedDoctorSpecialty: 'General Dentistry',
        assignedDoctorClinic: 'Nikhil Dental Studio',
        adminNotes: payloadWithInstructions,
      );

      service.addTestAssignedRequest(referralRequest);

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFFF8FAFC),
              body: RepaintBoundary(
                key: key,
                child: const DentistTimeline(initialTabIndex: 2),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify instruction header and clean instruction text
      expect(find.text('REFERRAL INSTRUCTIONS'), findsOneWidget);
      expect(find.text('Patient has mild dental anxiety. Pre-consultation reassuring call recommended.'), findsOneWidget);
      expect(find.textContaining('REFERRAL_PAYLOAD'), findsNothing);
      expect(find.textContaining('ref-999'), findsNothing);

      await _capturePngIfPossible(tester, key, '$artifactDir\\gs_health_doctor_requests_with_instructions.png');
    });
  });
}
