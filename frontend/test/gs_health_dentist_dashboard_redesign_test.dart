import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/widgets/denta_guru_logo.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';

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

      for (final family in ['Roboto', 'Plus Jakarta Sans', 'Outfit', 'Segoe UI']) {
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

    final nirmalaReg = File(r'C:\Windows\Fonts\Nirmala.ttf');
    final nirmalaBold = File(r'C:\Windows\Fonts\NirmalaB.ttf');
    if (nirmalaReg.existsSync()) {
      final nRegBytes = nirmalaReg.readAsBytesSync();
      final nBoldBytes =
          nirmalaBold.existsSync() ? nirmalaBold.readAsBytesSync() : nRegBytes;
      final nirmalaLoader = FontLoader('Nirmala UI')
        ..addFont(
          Future.value(ByteData.view(Uint8List.fromList(nRegBytes).buffer)),
        )
        ..addFont(
          Future.value(ByteData.view(Uint8List.fromList(nBoldBytes).buffer)),
        );
      await nirmalaLoader.load();
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
  for (final element in find.byType(Image).evaluate()) {
    final widget = element.widget as Image;
    await tester.runAsync(() async {
      await precacheImage(widget.image, element);
    });
  }
  await tester.pump();
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

  const String artifactDir =
      r'C:\Users\ADMIN\.gemini\antigravity\brain\0cdf62c7-364d-4c39-8424-4bae41245b5b';

  setUpAll(() async {
    await _loadRealFontsIfAvailable();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    await PatientProblemService().clearAllData();
  });

  void seedDentistWorkspaceData(PatientProblemService service) {
    final ananyaDoc = DoctorModel(
      id: 'doc-ananya-rao',
      userId: 'usr-ananya-rao',
      name: 'Dr. Ananya Rao',
      specialty: 'Endodontist',
      qualification: 'BDS, MDS',
      experienceYears: 9,
      rating: 4.9,
      reviewCount: 118,
      clinicName: 'Bandra West Dental Clinic',
      phone: '9820011223',
      email: 'ananya.rao@gshealth.in',
      status: 'Available',
      city: 'Mumbai',
      pincode: '400050',
      clinicAddress: 'Bandra West, Mumbai',
      languages: const ['English', 'Hindi', 'Marathi'],
      nextAvailableSlots: const ['09:30 AM', '10:00 AM', '11:00 AM'],
      consultationFee: '₹600',
    );

    final vikramDoc = DoctorModel(
      id: 'doc-vikram-mehta',
      userId: 'usr-vikram-mehta',
      name: 'Dr. Vikram Mehta',
      specialty: 'Orthodontist',
      qualification: 'BDS, MDS',
      experienceYears: 11,
      rating: 4.8,
      reviewCount: 94,
      clinicName: 'Bandra West Dental Clinic',
      phone: '9820099887',
      email: 'vikram.mehta@gshealth.in',
      status: 'Available',
      city: 'Bandra West',
      pincode: '400050',
      clinicAddress: 'Bandra West, Mumbai',
      languages: const ['English', 'Hindi'],
      nextAvailableSlots: const ['10:30 AM', '02:00 PM'],
      consultationFee: '₹700',
    );

    service.addTestDoctor(ananyaDoc);
    service.addTestDoctor(vikramDoc);
    service.currentDoctor = ananyaDoc;

    service.addTestClinic(
      ClinicModel(
        id: 'clinic-bandra-west',
        clinicName: 'Bandra West Dental Clinic',
        location: 'Bandra West, Mumbai',
        services: const ['Endodontics', 'Orthodontics', 'Implants'],
        pricing: const [
          {'name': 'Root Canal', 'price': '₹4,500'},
          {'name': 'Consultation', 'price': '₹600'},
        ],
      ),
    );

    service.updatePatientProfile(
      id: 'pat-riya-sharma',
      name: 'Riya Sharma',
      email: 'riya.sharma@gshealth.in',
      phone: '9000000200',
      age: '34',
      gender: 'Female',
      bloodGroup: 'O+',
      emergencyContact: '9000000200',
      city: 'Mumbai',
      pincode: '400050',
      languages: const ['English', 'Hindi'],
    );

    // Seed 10 unread notifications so badge displays "9+"
    for (int i = 1; i <= 10; i++) {
      service.addNotification(
        recipientRole: 'Dentist',
        recipientId: 'doc-ananya-rao',
        title: 'New Triage Case #$i',
        message: 'Assigned consultation request from Riya Sharma',
      );
    }

    // Seed 2 Assigned Triage Requests matching Screenshot 2
    service.addTestAssignedRequest(
      PatientConsultationRequest(
        id: 'req-triage-1',
        patientId: 'pat-riya-sharma',
        patientName: 'Riya Sharma',
        patientPhone: '+919000000200',
        problemCategory: 'Endodontist',
        problemDescription:
            'I have severe pain in my lower right molar for two days, worse with cold ...',
        symptoms: 'दांत में गंभीर दर्द और संवेदनाशीलता',
        severity: 'Severe',
        status: 'Assigned',
        assignedDoctorId: 'doc-ananya-rao',
        assignedDoctorName: 'Dr. Ananya Rao',
        assignedDoctorSpecialty: 'Endodontist',
        adminNotes: 'TEST_assign',
        submittedAt: DateTime(2026, 10, 19, 10, 30),
      ),
    );

    service.addTestAssignedRequest(
      PatientConsultationRequest(
        id: 'req-triage-2',
        patientId: 'pat-riya-sharma',
        patientName: 'Riya Sharma',
        patientPhone: '+919000000200',
        problemCategory: 'Endodontist',
        problemDescription:
            'I have severe pain in my lower right molar for two days, worse with cold ...',
        symptoms: 'दांत में गंभीर दर्द और संवेदनाशीलता',
        severity: 'Severe',
        status: 'Assigned',
        assignedDoctorId: 'doc-ananya-rao',
        assignedDoctorName: 'Dr. Ananya Rao',
        assignedDoctorSpecialty: 'Endodontist',
        adminNotes: 'TEST_assign',
        submittedAt: DateTime(2026, 10, 19, 14, 15),
      ),
    );

    // Seed 1 E-Prescription issued by Dr. Ananya Rao matching Screenshot 4
    service.addMedicalRecord({
      'id': 'rx_pericoronitis_1',
      'type': 'prescription',
      'title': 'E-Prescription: Likely pericoronitis around lower right wisdom tooth',
      'diagnosis': 'Likely pericoronitis around lower right wisdom tooth',
      'patientName': 'Riya Sharma',
      'doctorId': 'doc-ananya-rao',
      'doctorName': 'Dr. Ananya Rao',
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

  group('GS HEALTH Dentist Dashboard 5-Tab Redesign & Workflow Tests', () {
    testWidgets(
      '1. Today Default Landing Screen, Patients, Requests, Refer, and Rx tabs match reference screenshots and capture all 5 PNGs',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        seedDentistWorkspaceData(service);
        ApiService.debugUpdateDoctorAvailabilityOverride = (
          String doctorId,
          bool isAvailable, {
          String? statusOverride,
        }) async => {
          'success': true,
          'isAvailable': isAvailable,
          'availability_status': statusOverride ?? (isAvailable ? 'Available' : 'Unavailable'),
        };
        addTearDown(() => ApiService.debugUpdateDoctorAvailabilityOverride = null);

        final boundaryKey = GlobalKey();

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto', useMaterial3: false),
              home: RepaintBoundary(
                key: boundaryKey,
                child: const DentistTimelineScreen(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // ==========================================
        // TAB 0: TODAY (Default Landing Screen)
        // ==========================================
        expect(find.byType(GsHealthLogo), findsOneWidget);
        expect(find.text('Doctor workspace'), findsOneWidget);
        expect(find.byKey(const Key('dentist_header_name')), findsOneWidget);
        expect(find.text('Dr. Ananya Rao'), findsOneWidget);
        expect(find.byKey(const Key('dentist_notifications_button')), findsOneWidget);
        expect(find.text('9+'), findsOneWidget);
        expect(find.byKey(const Key('dentist_profile_button')), findsOneWidget);

        // Date Selector cards
        for (int i = 0; i < 7; i++) {
          expect(find.byKey(Key('dentist_date_card_$i')), findsOneWidget);
        }

        // Availability Card
        expect(find.byKey(const Key('dentist_availability_card')), findsOneWidget);
        expect(find.text('Availability'), findsOneWidget);
        expect(find.byKey(const Key('dentist_availability_status_badge')), findsOneWidget);
        expect(find.text('ON'), findsOneWidget);
        expect(
          find.text(
            'Visible in patient search and open for new appointment bookings.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('dentist_availability_switch')), findsOneWidget);

        // Sponsored Banner
        expect(find.byKey(const Key('dentist_sponsored_banner')), findsOneWidget);
        expect(find.text('SPONSORED'), findsOneWidget);
        expect(find.text('FIXED TEETH JUST IN 3 DAYS'), findsOneWidget);
        expect(find.text('Free course'), findsOneWidget);

        // Empty State for Today
        expect(
          find.byKey(const Key('dentist_no_appointments_empty_state')),
          findsOneWidget,
        );
        expect(find.text('No appointments'), findsOneWidget);
        expect(
          find.text('Nothing booked for this day. Enjoy your free time.'),
          findsOneWidget,
        );

        // Bottom Navigation Bar labels
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Patients'), findsOneWidget);
        expect(find.text('Requests'), findsOneWidget);
        expect(find.text('Refer'), findsOneWidget);
        expect(find.text('Rx'), findsOneWidget);

        // Capture Screenshot 1: gs_health_dentist_today.png
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_dentist_today.png',
        );

        // ==========================================
        // TAB 1: PATIENTS
        // ==========================================
        await tester.tap(find.text('Patients'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text('Clinical directory & shared files').evaluate().isNotEmpty ||
              find.text("Everyone you've cared for").evaluate().isNotEmpty,
          isTrue,
        );
        expect(find.text('Patients'), findsWidgets);
        expect(
          find.text('Dental records shared with you').evaluate().isNotEmpty ||
              find.text('My patients').evaluate().isNotEmpty,
          isTrue,
        );
        expect(find.text('Riya Sharma'), findsWidgets);

        // Capture Screenshot 2: gs_health_dentist_patients.png
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_dentist_patients.png',
        );

        // ==========================================
        // TAB 2: REQUESTS (Assigned requests)
        // ==========================================
        await tester.tap(find.text('Requests'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Triage cases & referrals routed to you'), findsOneWidget);
        expect(find.text('Assigned requests'), findsOneWidget);
        expect(find.byKey(const Key('requests_folder_button')), findsOneWidget);

        expect(find.byKey(const Key('assigned_request_card_req-triage-1')), findsOneWidget);
        expect(find.byKey(const Key('assigned_request_card_req-triage-2')), findsOneWidget);
        expect(find.text('HIGH URGENCY'), findsNWidgets(2));
        expect(find.text('Doctor assigned'), findsNWidgets(2));
        expect(find.text('दांत में गंभीर दर्द और संवेदनाशीलता'), findsNWidgets(2));
        expect(
          find.text(
            'I have severe pain in my lower right molar for two days, worse with cold ...',
          ),
          findsNWidgets(2),
        );
        expect(
          find.text('Riya Sharma · +91 9000000200').evaluate().isNotEmpty ||
              find.text('Riya Sharma · +919000000200').evaluate().isNotEmpty,
          isTrue,
        );
        expect(find.text('Suggested: Endodontist'), findsNWidgets(2));
        expect(find.text('Assigned to Dr. Ananya Rao'), findsNWidgets(2));
        expect(find.text('Mon, 19 Oct'), findsNWidgets(2));
        expect(find.text('ADMIN GUIDANCE'), findsNWidgets(2));
        expect(find.text('TEST_assign'), findsNWidgets(2));
        expect(find.byKey(const Key('accept_case_button_req-triage-1')), findsOneWidget);
        expect(find.text('Accept case'), findsNWidgets(2));

        // Capture Screenshot 3: gs_health_dentist_requests.png
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_dentist_requests.png',
        );

        // ==========================================
        // TAB 3: REFER (Refer to a specialist)
        // ==========================================
        await tester.tap(find.text('Refer').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Refer to a specialist'), findsOneWidget);
        expect(find.byKey(const Key('refer_history_button')), findsOneWidget);
        expect(find.byKey(const Key('refer_type_specialist_pill')), findsOneWidget);
        expect(find.byKey(const Key('refer_type_clinic_pill')), findsOneWidget);
        expect(find.text('Specialist doctor'), findsOneWidget);
        expect(find.text('Clinic'), findsOneWidget);

        expect(find.text('Patient details'), findsOneWidget);
        expect(
          find.text('Pick one of your patients or type details below'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('refer_patient_chip_Riya Sharma')), findsOneWidget);
        expect(find.text('PATIENT NAME'), findsOneWidget);
        expect(find.text('PATIENT MOBILE (+91)'), findsOneWidget);
        expect(find.text('AGE'), findsOneWidget);
        expect(find.byKey(const Key('dentist_refer_gender_Male')), findsOneWidget);
        expect(find.byKey(const Key('dentist_refer_gender_Female')), findsOneWidget);
        expect(find.byKey(const Key('dentist_refer_gender_Other')), findsOneWidget);
        expect(find.text('REFER TO'), findsOneWidget);
        expect(find.text('Dr. Vikram Mehta'), findsOneWidget);
        expect(find.text('Orthodontist · Bandra West'), findsOneWidget);

        // Capture Screenshot 4: gs_health_dentist_refer.png
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_dentist_refer.png',
        );

        // ==========================================
        // TAB 4: RX (E-prescriptions)
        // ==========================================
        await tester.tap(find.text('Rx'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Issued by you'), findsOneWidget);
        expect(find.text('E-prescriptions'), findsOneWidget);
        expect(find.byKey(const Key('dentist_new_rx_button')), findsOneWidget);
        expect(
          find.byKey(const Key('dentist_rx_card_rx_pericoronitis_1')),
          findsOneWidget,
        );
        expect(
          find.text('Likely pericoronitis around lower right wisdom tooth'),
          findsOneWidget,
        );
        expect(find.text('Riya Sharma · Tue, 20 Oct'), findsOneWidget);
        expect(find.text('E-PRESCRIPTION · 1 MEDICINE(S)'), findsOneWidget);
        expect(find.text('℞ Ibuprofen 400mg'), findsOneWidget);
        expect(find.text('1-0-1 · 3 days'), findsOneWidget);
        expect(find.text('Warm salt rinses; visit within 3 days'), findsOneWidget);

        // Capture Screenshot 5: gs_health_dentist_rx.png
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_dentist_rx.png',
        );
      },
    );

    testWidgets(
      '2. Interactive workflows: Date selector, Availability toggle, Accept case, Patient chip autofill & referral submission, and Rx expand/collapse',
      (tester) async {
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        seedDentistWorkspaceData(service);
        ApiService.debugUpdateDoctorAvailabilityOverride = (
          String doctorId,
          bool isAvailable, {
          String? statusOverride,
        }) async => {
          'success': true,
          'isAvailable': isAvailable,
          'availability_status': statusOverride ?? (isAvailable ? 'Available' : 'Unavailable'),
        };
        addTearDown(() => ApiService.debugUpdateDoctorAvailabilityOverride = null);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: DentistTimelineScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 1. Toggle Availability Switch on Today tab
        final switchFinder = find.byKey(const Key('dentist_availability_switch'));
        expect(tester.widget<Switch>(switchFinder).value, isTrue);
        await tester.tap(switchFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.widget<Switch>(switchFinder).value, isFalse);

        // 2. Select another Date card on Today tab
        await tester.tap(find.byKey(const Key('dentist_date_card_1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('No appointments'), findsOneWidget);

        // 3. Go to Requests tab and tap "Accept case"
        await tester.tap(find.text('Requests'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final acceptBtn = find.byKey(const Key('accept_case_button_req-triage-1'));
        expect(acceptBtn, findsOneWidget);
        await tester.tap(acceptBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Accepted'), findsOneWidget);
        expect(find.text('Case accepted'), findsOneWidget);

        // 4. Go to Refer tab, tap Riya Sharma chip to autofill, select Dr. Vikram Mehta, and submit
        await tester.tap(find.text('Refer').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byKey(const Key('refer_patient_chip_Riya Sharma')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final nameField = tester.widget<TextFormField>(
          find.byKey(const Key('dentist_refer_patient_name')),
        );
        final phoneField = tester.widget<TextFormField>(
          find.byKey(const Key('dentist_refer_patient_phone')),
        );
        expect(nameField.controller?.text, 'Riya Sharma');
        expect(phoneField.controller?.text, '9000000200');

        // Select Dr. Vikram Mehta card
        final vikramCard = find.byKey(const Key('dentist_refer_doctor_doc-vikram-mehta'));
        await tester.ensureVisible(vikramCard);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(vikramCard);
        await tester.pump(const Duration(milliseconds: 200));

        // Stub referral creation API for headless test & scroll Send button cleanly above bottom nav
        ApiService.debugCreatePatientReferralOverride = ({
          required String referredPatientName,
          required String referredPatientMobile,
          required String doctorId,
          String? referrerPatientId,
        }) async => {
          'success': true,
          'referral': {
            'id': 'ref-dentist-tab-1',
            'referrerPatientId': referrerPatientId ?? 'doc-ananya-rao',
            'referredPatientName': referredPatientName,
            'referredPatientMobile': referredPatientMobile,
            'doctorId': doctorId,
            'doctorName': 'Dr. Vikram Mehta',
            'requiredSpecialist': 'Orthodontist',
            'clinicalComplaint': 'Specialist referral consultation requested',
            'status': 'Pending',
            'referralDate': DateTime.now().toIso8601String(),
          },
        };
        addTearDown(() => ApiService.debugCreatePatientReferralOverride = null);

        // Wait for any earlier availability SnackBar (3s) to dismiss, then scroll to Send button
        await tester.pump(const Duration(seconds: 4));
        await tester.drag(find.byKey(const Key('dentist_refer_scroll_view')), const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 200));
        final sendBtn = find.byKey(const Key('dentist_send_referral_button'));
        await tester.ensureVisible(sendBtn);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(sendBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(service.myCreatedPatientReferrals.isNotEmpty, isTrue);
        expect(
          service.myCreatedPatientReferrals.first.referredPatientName,
          'Riya Sharma',
        );
        expect(
          service.myCreatedPatientReferrals.first.doctorName,
          'Dr. Vikram Mehta',
        );

        // 5. Go to Rx tab and test collapsing & expanding prescription card
        await tester.tap(find.text('Rx'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('℞ Ibuprofen 400mg'), findsOneWidget);
        await tester.tap(find.byKey(const Key('dentist_rx_toggle_rx_pericoronitis_1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('℞ Ibuprofen 400mg'), findsNothing);

        await tester.tap(find.byKey(const Key('dentist_rx_toggle_rx_pericoronitis_1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('℞ Ibuprofen 400mg'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Multi-viewport responsiveness across 320px, 360px, 390px, and 412px widths with zero RenderFlex overflows',
      (tester) async {
        final service = PatientProblemService();
        seedDentistWorkspaceData(service);
        ApiService.debugUpdateDoctorAvailabilityOverride = (
          String doctorId,
          bool isAvailable, {
          String? statusOverride,
        }) async => {
          'success': true,
          'isAvailable': isAvailable,
          'availability_status': statusOverride ?? (isAvailable ? 'Available' : 'Unavailable'),
        };
        addTearDown(() => ApiService.debugUpdateDoctorAvailabilityOverride = null);

        for (final width in [320.0, 360.0, 390.0, 412.0]) {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                home: DentistTimelineScreen(),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));

          for (final tabLabel in ['Today', 'Patients', 'Requests', 'Refer', 'Rx']) {
            await tester.tap(find.text(tabLabel).last);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 250));
            expect(tester.takeException(), isNull);
          }
        }

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
  });
}
