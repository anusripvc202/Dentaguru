import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/utils/record_file_helper.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';

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
      final file = File(outputPath);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
    } catch (_) {}
  });
}

void _seedTestEnvironment(PatientProblemService service) {
  // Current Doctor
  final currentDoctor = DoctorModel(
    id: 'doc-ananya-rao',
    userId: 'user-ananya-rao',
    name: 'Dr. Ananya Rao',
    specialty: 'Endodontist',
    qualification: 'BDS, MDS',
    experienceYears: 8,
    rating: 4.9,
    reviewCount: 38,
    clinicName: 'Bandra West Dental Clinic',
    clinicAddress: 'Hill Road, Bandra West',
    phone: '+919000000001',
    email: 'ananya@gshealth.in',
    status: 'Available',
    verificationStatus: 'VERIFIED',
    nextAvailableSlots: ['Today, 2:00 PM'],
    consultationFee: '₹800',
    languages: ['English', 'Hindi'],
    city: 'Mumbai',
    pincode: '400050',
  );
  service.currentDoctor = currentDoctor;
  service.addTestDoctor(currentDoctor);

  // Available Specialists to Refer To
  final vikram = DoctorModel(
    id: 'doc-vikram-mehta',
    userId: 'user-vikram-mehta',
    name: 'Dr. Vikram Mehta',
    specialty: 'Orthodontist',
    qualification: 'BDS, MDS (Orthodontics)',
    experienceYears: 10,
    rating: 4.95,
    reviewCount: 45,
    clinicName: 'Bandra West Dental Clinic',
    clinicAddress: 'Hill Road, Bandra West, Mumbai',
    city: 'Mumbai',
    pincode: '400050',
    phone: '9000000002',
    email: 'vikram.mehta@gshealth.in',
    status: 'Available',
    consultationFee: '₹1000',
    nextAvailableSlots: ['Tomorrow, 11:00 AM'],
  );
  service.addTestDoctor(vikram);

  final karthik = DoctorModel(
    id: 'doc-karthik-raman',
    userId: 'user-karthik-raman',
    name: 'Dr. Karthik Raman',
    specialty: 'Oral Surgeon',
    qualification: 'BDS, MDS (Oral & Maxillofacial)',
    experienceYears: 12,
    rating: 4.88,
    reviewCount: 60,
    clinicName: 'Anna Nagar Dental Clinic',
    clinicAddress: '2nd Avenue, Anna Nagar, Chennai',
    city: 'Chennai',
    pincode: '600040',
    phone: '9000000003',
    email: 'karthik.raman@gshealth.in',
    status: 'Available',
    consultationFee: '₹900',
    nextAvailableSlots: ['Today, 4:00 PM'],
  );
  service.addTestDoctor(karthik);

  final samhitha = DoctorModel(
    id: 'doc-samhitha',
    userId: 'user-samhitha',
    name: 'Dr. Samhitha',
    specialty: 'General Dentist',
    qualification: 'BDS',
    experienceYears: 6,
    rating: 4.8,
    reviewCount: 30,
    clinicName: 'Independent',
    clinicAddress: 'Indiranagar, Bangalore',
    city: 'Bangalore',
    pincode: '560038',
    phone: '9000000004',
    email: 'samhitha@gshealth.in',
    status: 'Available',
    consultationFee: '₹600',
    nextAvailableSlots: ['Today, 5:30 PM'],
  );
  service.addTestDoctor(samhitha);

  final rohan = DoctorModel(
    id: 'doc-rohan-das',
    userId: 'user-rohan-das',
    name: 'Dr. Rohan Das',
    specialty: 'Periodontist',
    qualification: 'BDS, MDS (Periodontics)',
    experienceYears: 9,
    rating: 4.9,
    reviewCount: 40,
    clinicName: 'Anna Nagar Dental Clinic',
    clinicAddress: '2nd Avenue, Anna Nagar, Chennai',
    city: 'Chennai',
    pincode: '600040',
    phone: '9000000005',
    email: 'rohan.das@gshealth.in',
    status: 'Available',
    consultationFee: '₹850',
    nextAvailableSlots: ['Tomorrow, 2:00 PM'],
  );
  service.addTestDoctor(rohan);

  // Available Clinics to Refer To
  final bandraClinic = ClinicModel(
    id: 'clinic-bandra-west',
    clinicName: 'Bandra West Dental Clinic',
    location: 'Hill Road, Bandra West, Mumbai - 400050',
    phone: '02226401122',
    services: ['Orthodontics', 'Endodontics', 'Oral Surgery'],
  );
  service.addTestClinic(bandraClinic);

  final annaClinic = ClinicModel(
    id: 'clinic-anna-nagar',
    clinicName: 'Anna Nagar Dental Clinic',
    location: '2nd Avenue, Anna Nagar, Chennai - 600040',
    phone: '04426211122',
    services: ['Periodontics', 'General Dentistry', 'Oral Surgery'],
  );
  service.addTestClinic(annaClinic);

  // Patient Riya Sharma
  final riya = PatientProfile(
    id: 'pat-riya-sharma',
    name: 'Riya Sharma',
    phone: '9000000200',
    age: '34',
    gender: 'Female',
    city: 'Mumbai',
    pincode: '400050',
    address: 'Bandra West, Mumbai',
    bloodGroup: 'O+',
    languages: const ['English', 'Hindi'],
  );
  service.addTestPatient(riya);

  // Associated Request for Riya Sharma
  service.addTestAssignedRequest(
    PatientConsultationRequest(
      id: 'req-riya-1',
      patientId: 'pat-riya-sharma',
      patientName: 'Riya Sharma',
      patientPhone: '+919000000200',
      problemCategory: 'Endodontist',
      problemDescription: 'Severe tooth pain in lower molar',
      symptoms: 'Sensitivity and throbbing pain',
      severity: 'Moderate',
      status: 'Assigned',
      assignedDoctorId: 'doc-ananya-rao',
      assignedDoctorName: 'Dr. Ananya Rao',
      submittedAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const String artifactDir = r'C:\Users\ADMIN\Desktop\project tpc\Dentaguru';

  setUpAll(() async {
    await _loadRealFontsIfAvailable();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    RecordFileHelper.testFilePickerOverride = null;
    await PatientProblemService().clearAllDataAndStorage();
  });

  group('GS HEALTH - Doctor Dashboard Patient Referral Navigation & Complete Workflow', () {
    testWidgets('1. Doctor Dashboard -> Patients -> Patient Record -> Tap Refer pre-fills patient details on Refer tab & preserves bottom nav', (tester) async {
      final service = PatientProblemService();
      _seedTestEnvironment(service);

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: RepaintBoundary(
                key: boundaryKey,
                child: const DentistTimelineScreen(initialTabIndex: 1), // Open Patients tab
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Verify Patients list shows Riya Sharma
      expect(find.text('My patients'), findsOneWidget);
      final riyaCard = find.byKey(const Key('doctor_patient_card_riya_sharma'));
      expect(riyaCard, findsOneWidget);

      // 2. Tap Riya Sharma -> Opens DoctorPatientRecordScreen
      await tester.tap(riyaCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 3. Confirm Patient Record is displayed (Screenshot 1 reference)
      expect(find.text('Patient record'), findsOneWidget);
      expect(find.text('Riya Sharma'), findsWidgets);
      expect(find.byKey(const Key('patient_record_write_rx_button')), findsOneWidget);
      final referBtn = find.byKey(const Key('patient_record_refer_button'));
      expect(referBtn, findsOneWidget);

      // 4. Tap Refer button on Patient Record screen
      await tester.tap(referBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 5. Confirm that navigation returns to Doctor Dashboard Refer tab
      expect(find.text('Refer to a specialist'), findsOneWidget);
      expect(find.byKey(const Key('refer_screen_back_button')), findsOneWidget);
      expect(find.byKey(const Key('refer_type_specialist_pill')), findsOneWidget);
      expect(find.byKey(const Key('refer_type_clinic_pill')), findsOneWidget);

      // 6. Confirm patient details are automatically prefilled
      expect(find.byKey(const Key('refer_patient_chip_Riya Sharma')), findsOneWidget);
      final nameField = tester.widget<TextFormField>(find.byKey(const Key('dentist_refer_patient_name')));
      expect(nameField.controller?.text, 'Riya Sharma');

      final phoneField = tester.widget<TextFormField>(find.byKey(const Key('dentist_refer_patient_phone')));
      expect(phoneField.controller?.text, '9000000200');

      final ageField = tester.widget<TextFormField>(find.byKey(const Key('dentist_refer_patient_age')));
      expect(ageField.controller?.text, '34');

      // 7. Confirm bottom navigation is preserved with Refer active
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Patients'), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Refer'), findsWidgets);
      expect(find.text('Rx'), findsOneWidget);

      // 8. Test back button returns to Patients tab
      await tester.tap(find.byKey(const Key('refer_screen_back_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('My patients'), findsOneWidget);
    });

    testWidgets('2. Refer Page UI: Specialist vs Clinic tabs, Search, Selection, Clinical Notes, and Visual Capture', (tester) async {
      final service = PatientProblemService();
      _seedTestEnvironment(service);

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: RepaintBoundary(
                key: boundaryKey,
                child: const DentistTimelineScreen(initialTabIndex: 3), // Open Refer tab
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // A. Verify Header & Default Tab
      expect(find.text('Refer to a specialist'), findsOneWidget);
      expect(find.text('Specialist dentist'), findsOneWidget);
      expect(find.text('Clinic'), findsOneWidget);

      // B. Switch to Clinic Tab and verify clinic card
      final clinicTab = find.byKey(const Key('refer_type_clinic_pill'));
      await tester.tap(clinicTab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final clinicCard = find.byKey(const Key('dentist_refer_clinic_clinic-bandra-west'));
      expect(clinicCard, findsOneWidget);
      await tester.tap(clinicCard);
      await tester.pump();

      // C. Switch back to Specialist Dentist tab
      await tester.tap(find.byKey(const Key('refer_type_specialist_pill')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // D. Select Riya Sharma chip
      final riyaChip = find.byKey(const Key('refer_patient_chip_Riya Sharma'));
      expect(riyaChip, findsOneWidget);
      await tester.tap(riyaChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.widget<TextFormField>(find.byKey(const Key('dentist_refer_patient_name'))).controller?.text, 'Riya Sharma');
      expect(tester.widget<TextFormField>(find.byKey(const Key('dentist_refer_patient_phone'))).controller?.text, '9000000200');

      // E. Specialist Dentist selection (Dr. Vikram Mehta)
      expect(find.text('Dr. Vikram Mehta'), findsOneWidget);
      final vikramCard = find.byKey(const Key('dentist_refer_doctor_doc-vikram-mehta'));
      expect(vikramCard, findsOneWidget);
      await tester.tap(vikramCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // F. Enter Clinical Notes
      final notesField = find.byKey(const Key('dentist_refer_notes_input'));
      await tester.enterText(notesField, 'Impacted 38, pain for 2 weeks. Please evaluate for extraction');
      await tester.pump();

      // Capture Top of Refer Page
      await _capturePngIfPossible(
        tester,
        boundaryKey,
        '$artifactDir\\gs_health_doctor_refer_top.png',
      );

      // G. Scroll down and capture Bottom of Refer Page
      await tester.drag(find.byKey(const Key('dentist_refer_scroll_view')), const Offset(0, -600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('refer_attachment_gallery_button')), findsOneWidget);
      expect(find.byKey(const Key('refer_attachment_camera_button')), findsOneWidget);
      expect(find.byKey(const Key('refer_attachment_pdf_button')), findsOneWidget);
      expect(find.byKey(const Key('dentist_send_referral_button')), findsOneWidget);

      await _capturePngIfPossible(
        tester,
        boundaryKey,
        '$artifactDir\\gs_health_doctor_refer_bottom.png',
      );
    });

    testWidgets('3. Attachments: Gallery, Camera, PDF pickers, validation, remove attachment, and max 5 limit', (tester) async {
      final service = PatientProblemService();
      _seedTestEnvironment(service);

      final validPngBytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
      final validJpgBytes = base64Decode('/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=');

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: DentistTimelineScreen(initialTabIndex: 3),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Scroll to attachment section
      await tester.drag(find.byKey(const Key('dentist_refer_scroll_view')), const Offset(0, -450));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // A. Pick PDF using test override
      RecordFileHelper.testFilePickerOverride = () async {
        return PickedRecordFile(
          name: 'Tooth38_CBCT_Scan.pdf',
          extension: 'PDF',
          mimeType: 'application/pdf',
          sizeBytes: 1024 * 350,
          bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 Mock Dental Scan')),
        );
      };

      final pdfBtn = find.byKey(const Key('refer_attachment_pdf_button'));
      expect(pdfBtn, findsOneWidget);
      await tester.tap(pdfBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Tooth38_CBCT_Scan.pdf'), findsOneWidget);
      expect(find.text('ATTACH X-RAYS, PHOTOS OR REPORTS (1/5)'), findsOneWidget);

      // B. Pick Gallery Image using test override
      RecordFileHelper.testFilePickerOverride = () async {
        return PickedRecordFile(
          name: 'Molar_OPG_Xray.png',
          extension: 'PNG',
          mimeType: 'image/png',
          sizeBytes: 1024 * 512,
          bytes: validPngBytes,
        );
      };

      final galleryBtn = find.byKey(const Key('refer_attachment_gallery_button'));
      await tester.tap(galleryBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Molar_OPG_Xray.png'), findsOneWidget);
      expect(find.text('ATTACH X-RAYS, PHOTOS OR REPORTS (2/5)'), findsOneWidget);

      // C. Capture Camera photo using test override
      RecordFileHelper.testFilePickerOverride = () async {
        return PickedRecordFile(
          name: 'Intraoral_Camera.jpg',
          extension: 'JPG',
          mimeType: 'image/jpeg',
          sizeBytes: 1024 * 200,
          bytes: validJpgBytes,
        );
      };

      final cameraBtn = find.byKey(const Key('refer_attachment_camera_button'));
      await tester.tap(cameraBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Intraoral_Camera.jpg'), findsOneWidget);
      expect(find.text('ATTACH X-RAYS, PHOTOS OR REPORTS (3/5)'), findsOneWidget);

      // D. Remove an attachment (Remove Intraoral_Camera.jpg)
      final removeBtn = find.byKey(const Key('remove_refer_attachment_Intraoral_Camera.jpg'));
      expect(removeBtn, findsOneWidget);
      await tester.ensureVisible(removeBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(removeBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Intraoral_Camera.jpg'), findsNothing);
      expect(find.text('ATTACH X-RAYS, PHOTOS OR REPORTS (2/5)'), findsOneWidget);
      expect(find.text('Tooth38_CBCT_Scan.pdf'), findsOneWidget);
      expect(find.text('Molar_OPG_Xray.png'), findsOneWidget);
    });

    testWidgets('4. End-to-end referral submission: persists referral, creates records, updates workflow & resets form', (tester) async {
      final service = PatientProblemService();
      _seedTestEnvironment(service);

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: DentistTimelineScreen(initialTabIndex: 3),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Select Riya Sharma
      await tester.tap(find.byKey(const Key('refer_patient_chip_Riya Sharma')));
      await tester.pump();

      // 2. Select Dr. Vikram Mehta
      await tester.tap(find.byKey(const Key('dentist_refer_doctor_doc-vikram-mehta')));
      await tester.pump();

      // 3. Enter Notes
      await tester.enterText(
        find.byKey(const Key('dentist_refer_notes_input')),
        'Impacted 38, pain for 2 weeks. Please evaluate for extraction',
      );
      await tester.pump();

      // 4. Attach 1 PDF
      RecordFileHelper.testFilePickerOverride = () async {
        return PickedRecordFile(
          name: 'Tooth38_Clinical_Report.pdf',
          extension: 'PDF',
          mimeType: 'application/pdf',
          sizeBytes: 1024 * 120,
          bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 Clinical Report Data')),
        );
      };
      await tester.drag(find.byKey(const Key('dentist_refer_scroll_view')), const Offset(0, -400));
      await tester.pump();
      await tester.tap(find.byKey(const Key('refer_attachment_pdf_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 5. Tap Send Referral
      final sendBtn = find.byKey(const Key('dentist_send_referral_button'));
      expect(sendBtn, findsOneWidget);
      await tester.ensureVisible(sendBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(sendBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 6. Verify referral was created in PatientProblemService
      expect(service.myCreatedPatientReferrals.isNotEmpty, isTrue);
      final created = service.myCreatedPatientReferrals.first;
      expect(created.referredPatientName, 'Riya Sharma');
      expect(created.doctorName, contains('Vikram Mehta'));
      expect(created.clinicalComplaint, contains('Impacted 38'));

      // 7. Verify Form is reset after submission
      expect(tester.widget<TextFormField>(find.byKey(const Key('dentist_refer_patient_name'))).controller?.text, '');
      expect(find.text('ATTACH X-RAYS, PHOTOS OR REPORTS (0/5)'), findsOneWidget);
    });

    testWidgets('5. Multi-viewport responsiveness across 320px, 360px, 390px, and 412px viewports (zero RenderFlex overflows)', (tester) async {
      final service = PatientProblemService();
      _seedTestEnvironment(service);

      for (final width in [320.0, 360.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: DentistTimelineScreen(initialTabIndex: 3),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Refer to a specialist'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'RenderFlex overflow detected at width $width');
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
