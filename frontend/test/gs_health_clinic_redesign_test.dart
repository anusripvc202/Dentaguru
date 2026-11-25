import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/theme/app_theme.dart';
import 'package:dentaguru/features/auth/presentation/screens/auth_screen.dart';
import 'package:dentaguru/features/clinic/presentation/screens/clinic_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kArtifactsDir =
    r'C:\Users\ADMIN\.gemini\antigravity\brain\0cdf62c7-364d-4c39-8424-4bae41245b5b';

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

      for (final family in [
        'Roboto',
        'Plus Jakarta Sans',
        'Outfit',
        'Segoe UI',
      ]) {
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

Future<void> _capturePng(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    try {
      final boundary =
          boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final outFile = File('$_kArtifactsDir\\$filename');
      await outFile.writeAsBytes(byteData.buffer.asUint8List());
    } catch (_) {}
  });
}

void _installGoogleFontsAssetHandler(WidgetTester tester) {
  final regFile = File(r'C:\Windows\Fonts\segoeui.ttf');
  final boldFile = File(r'C:\Windows\Fonts\segoeuib.ttf');
  final regBytes = regFile.existsSync() ? regFile.readAsBytesSync() : Uint8List(0);
  final boldBytes =
      boldFile.existsSync() ? boldFile.readAsBytesSync() : regBytes;

  final manifestFile = File('build/unit_test_assets/AssetManifest.bin');
  final Map<Object?, Object?> manifestMap = <Object?, Object?>{};
  if (manifestFile.existsSync()) {
    final decoded = const StandardMessageCodec().decodeMessage(
      ByteData.sublistView(manifestFile.readAsBytesSync()),
    );
    if (decoded is Map) {
      manifestMap.addAll(decoded.cast<Object?, Object?>());
    }
  }

  const fontAssets = <String>[
    'google_fonts/PlusJakartaSans-Regular.ttf',
    'google_fonts/PlusJakartaSans-Medium.ttf',
    'google_fonts/PlusJakartaSans-SemiBold.ttf',
    'google_fonts/PlusJakartaSans-Bold.ttf',
    'google_fonts/PlusJakartaSans-ExtraBold.ttf',
    'google_fonts/Outfit-Regular.ttf',
    'google_fonts/Outfit-Medium.ttf',
    'google_fonts/Outfit-SemiBold.ttf',
    'google_fonts/Outfit-Bold.ttf',
  ];
  for (final asset in fontAssets) {
    manifestMap[asset] = <Object?>[
      <Object?, Object?>{'asset': asset},
    ];
  }
  final encodedManifest = const StandardMessageCodec().encodeMessage(manifestMap);

  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    'flutter/assets',
    (ByteData? message) async {
      if (message == null) return null;
      final key = utf8.decode(message.buffer.asUint8List());
      if (key == 'AssetManifest.bin') {
        return encodedManifest;
      }
      if (key.startsWith('google_fonts/')) {
        final bytes =
            (key.contains('Bold') || key.contains('SemiBold'))
                ? boldBytes
                : regBytes;
        return ByteData.sublistView(bytes);
      }
      final builtFile = File('build/unit_test_assets/$key');
      if (builtFile.existsSync()) {
        return ByteData.sublistView(builtFile.readAsBytesSync());
      }
      final directFile = File(key);
      if (directFile.existsSync()) {
        return ByteData.sublistView(directFile.readAsBytesSync());
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFontsIfAvailable();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ApiService.debugLoginOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    ApiService.debugRequestOtpOverride = null;
    ApiService.debugVerifyOtpOverride = null;
    ApiService.debugLoginOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  testWidgets(
    '1. Clinic Sign-In role option renders cleanly, supports OTP verification, and routes to Clinic Dashboard',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async => {
        'success': true,
        'message': 'One-time code sent',
        'otp': '123456',
        'deliveryMode': 'on_screen',
      };
      ApiService.debugVerifyOtpOverride = ({required String phone, String email = '', required String code}) async => {
        'success': code == '123456',
        'message': code == '123456' ? 'OTP Verified' : 'Invalid code',
      };
      ApiService.debugLoginOverride = ({
        String? email,
        String? otp,
        String? password,
        String? phone,
        String? role,
      }) async {
        return {
          'success': true,
          'token': 'clinic-jwt-token',
          'user': {
            'id': 'cln-user-1',
            'name': 'Apex Smile Care Center',
            'clinicName': 'Apex Smile Care Center',
            'location': 'Jubilee Hills Road 36, Hyderabad',
            'phone': phone ?? email ?? '',
            'email': 'contact@apexsmile.com',
            'role': role ?? 'Clinic',
            'isFeatured': true,
          },
        };
      };

      final boundaryKey = GlobalKey();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => RepaintBoundary(
              key: boundaryKey,
              child: const AuthScreen(),
            ),
          ),
          GoRoute(
            path: '/clinic',
            builder: (_, __) => const ClinicDashboardScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signin_role_patient')), findsOneWidget);
      expect(find.byKey(const Key('signin_role_dentist')), findsOneWidget);
      expect(find.byKey(const Key('signin_role_clinic')), findsOneWidget);
      expect(find.byKey(const Key('signin_role_admin')), findsNothing);
      expect(find.text('DEMO ACCOUNTS · TAP TO FILL'), findsNothing);

      // Select Clinic option and capture Login PNG
      await tester.tap(find.byKey(const Key('signin_role_clinic')));
      await tester.pumpAndSettle();

      await _capturePng(tester, boundaryKey, 'gs_health_clinic_login.png');

      // Enter registered clinic mobile number and request OTP
      await tester.enterText(find.byType(TextFormField).first, '9988776655');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Send code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Enter your code'), findsOneWidget);
      expect(find.text('Fill'), findsOneWidget);

      await tester.tap(find.text('Fill'));
      await tester.pumpAndSettle();

      final verifyBtn =
          find.widgetWithText(ElevatedButton, 'Verify & continue');
      if (verifyBtn.evaluate().isNotEmpty) {
        await tester.tap(verifyBtn);
        await tester.pumpAndSettle();
      }

      expect(find.byType(ClinicDashboardScreen), findsOneWidget);
      expect(find.text('Clinic dashboard'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('clinic_header_name')))
            .data,
        equals('Apex Smile Care Center'),
      );
      expect(find.text('Apex Smile Care Center'), findsWidgets);
      expect(
        SessionService().currentSession?.role.toLowerCase(),
        equals('clinic'),
      );
      expect(
        PatientProblemService().authenticatedClinicName,
        equals('Apex Smile Care Center'),
      );
    },
  );

  testWidgets(
    '2. Clinic Overview renders clean empty state without hardcoded dummy data',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ClinicDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clinic dashboard'), findsOneWidget);
      expect(find.text('Clinic Workspace'), findsWidgets);
      expect(find.text('Bandra West Dental Clinic'), findsNothing);
      expect(find.textContaining('Hill Road'), findsNothing);
      expect(find.text('Advertise on DentaGuru'), findsNothing);
      expect(find.text('Advertise on GS HEALTH'), findsOneWidget);
      expect(find.text('Attached doctors (0)'), findsOneWidget);
      expect(find.text('No doctors attached yet'), findsOneWidget);
    },
  );

  testWidgets(
    '3. Clinic Overview shows live metrics, isolated team, captures Overview Top/Bottom PNGs, and persists actions',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final service = PatientProblemService();
      service.addTestClinic(
        ClinicModel(
          id: 'cln-apex-1',
          clinicName: 'Apex Smile Care Center',
          location: 'Jubilee Hills Road 36, Hyderabad',
          phone: '9988776655',
          isFeatured: true,
          featuredPlan: 'Monthly Spotlight',
        ),
      );
      service.setAuthenticatedClinicSession(
        id: 'cln-apex-1',
        clinicName: 'Apex Smile Care Center',
        location: 'Jubilee Hills Road 36, Hyderabad',
        phone: '9988776655',
        isFeatured: true,
        featuredPlan: 'Monthly Spotlight',
      );

      service.addTestDoctor(
        DoctorModel(
          id: 'doc-apex-1',
          name: 'Dr. Ananya Rao',
          specialty: 'Endodontist',
          qualification: 'BDS, MDS',
          experienceYears: 11,
          rating: 4.9,
          reviewCount: 40,
          clinicName: 'Apex Smile Care Center',
          phone: '9800011122',
          email: 'ananya@apexsmile.com',
          status: 'Available',
          verificationStatus: 'VERIFIED',
          nextAvailableSlots: const ['10:00 AM', '03:00 PM'],
          consultationFee: '₹600',
        ),
      );
      service.addTestDoctor(
        DoctorModel(
          id: 'doc-apex-2',
          name: 'Dr. Rohan Kapoor',
          specialty: 'Orthodontist',
          qualification: 'BDS, MDS',
          experienceYears: 8,
          rating: 4.8,
          reviewCount: 25,
          clinicName: 'Apex Smile Care Center',
          phone: '9800033344',
          email: 'rohan@apexsmile.com',
          status: 'Available',
          verificationStatus: 'VERIFIED',
          nextAvailableSlots: const ['11:00 AM', '05:00 PM'],
          consultationFee: '₹700',
        ),
      );
      // Doctor from another clinic MUST stay isolated and hidden
      service.addTestDoctor(
        DoctorModel(
          id: 'doc-other-99',
          name: 'Dr. Unrelated Clinic',
          specialty: 'Prosthodontist',
          qualification: 'MDS',
          experienceYears: 6,
          rating: 4.5,
          reviewCount: 10,
          clinicName: 'Other Dental Studio',
          phone: '9800099988',
          email: 'other@studio.com',
          status: 'Available',
          nextAvailableSlots: const ['09:00 AM'],
          consultationFee: '₹500',
        ),
      );

      final today = DateTime.now();
      final todayIso =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      service.addTestRequest(
        PatientConsultationRequest(
          id: 'bk-1',
          patientName: 'Riya Sharma',
          patientPhone: '+919000000200',
          problemCategory: 'IN-CLINIC · Root Canal',
          problemDescription: 'Tooth sensitivity in lower molar',
          severity: 'Moderate',
          submittedAt: today,
          status: 'Pending',
          assignedDoctorId: 'doc-apex-1',
          assignedDoctorName: 'Dr. Ananya Rao',
          assignedDoctorClinic: 'Apex Smile Care Center',
          confirmedDate: todayIso,
          confirmedTimeSlot: '15:00',
        ),
      );
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'bk-2',
          patientName: 'Vikram Nair',
          patientPhone: '+919111122233',
          problemCategory: 'AUDIO CALL · Braces',
          problemDescription: 'Retainer follow up check',
          severity: 'Mild',
          submittedAt: today,
          status: 'Pending',
          assignedDoctorId: 'doc-apex-1',
          assignedDoctorName: 'Dr. Ananya Rao',
          assignedDoctorClinic: 'Apex Smile Care Center',
          confirmedDate: '2026-12-05',
          confirmedTimeSlot: '11:00',
        ),
      );
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'bk-3',
          patientName: 'Meera Krishnan',
          patientPhone: '+919222233344',
          problemCategory: 'IN-CLINIC · Aligners',
          problemDescription: 'Completed orthodontic scan',
          severity: 'Mild',
          submittedAt: today,
          status: 'Completed',
          assignedDoctorId: 'doc-apex-2',
          assignedDoctorName: 'Dr. Rohan Kapoor',
          assignedDoctorClinic: 'Apex Smile Care Center',
          confirmedDate: todayIso,
          confirmedTimeSlot: '10:00',
        ),
      );
      service.addNotification(
        recipientRole: 'Clinic',
        recipientId: 'cln-apex-1',
        title: 'New Booking Request',
        message: 'Riya Sharma requested a 15:00 visit.',
      );

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: RepaintBoundary(
              key: boundaryKey,
              child: const ClinicDashboardScreen(
                clinicName: 'Apex Smile Care Center',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Overview Top assertions
      expect(find.text('Apex Smile Care Center'), findsWidgets);
      expect(find.text('Jubilee Hills Road 36, Hyderabad'), findsOneWidget);
      expect(find.text("You're a Featured clinic"), findsOneWidget);
      expect(find.text('Dr. Unrelated Clinic'), findsNothing);

      await _capturePng(
        tester,
        boundaryKey,
        'gs_health_clinic_overview_top.png',
      );

      // Scroll down to view cards, 4 stats, and Attached doctors
      await tester.ensureVisible(
        find.byKey(const Key('clinic_doctor_card_doc-apex-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Patient referrals'), findsOneWidget);
      expect(find.text('Advertise on GS HEALTH'), findsOneWidget);
      expect(find.text('Visits today'), findsOneWidget);
      expect(find.text('Awaiting confirmation'), findsOneWidget);
      expect(find.text('Completed visits'), findsOneWidget);
      expect(find.text('Attached doctors'), findsOneWidget);
      expect(find.text('Attached doctors (2)'), findsOneWidget);
      expect(find.text('Dr. Ananya Rao'), findsOneWidget);
      expect(find.text('VERIFIED'), findsNWidgets(2));

      await _capturePng(
        tester,
        boundaryKey,
        'gs_health_clinic_overview_bottom.png',
      );

      // Edit details persists
      await tester.ensureVisible(
        find.byKey(const Key('clinic_edit_details_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clinic_edit_details_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('edit_clinic_name_field')),
        'Apex Dental & Implant Care',
      );
      await tester.enterText(
        find.byKey(const Key('edit_clinic_location_field')),
        'Banjara Hills Road 12, Hyderabad',
      );
      await tester.tap(find.byKey(const Key('save_clinic_details_button')));
      await tester.pumpAndSettle();

      expect(find.text('Apex Dental & Implant Care'), findsWidgets);
      expect(find.text('Banjara Hills Road 12, Hyderabad'), findsOneWidget);

      // Advertise on GS HEALTH submits admin notification
      await tester.ensureVisible(find.byKey(const Key('clinic_advertise_card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clinic_advertise_card')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('advertise_headline_field')),
        'Free Smile Checkup Week',
      );
      await tester.tap(
        find.byKey(const Key('submit_advertise_request_button')),
      );
      await tester.pumpAndSettle();

      expect(
        service.appNotifications.any(
          (n) =>
              n.recipientRole == 'Admin' &&
              n.message.contains('Free Smile Checkup Week'),
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    '4. Clinic Bookings tab supports filters, conflict detection, Confirm/Cancel persistence, and captures Bookings PNG',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final service = PatientProblemService();
      service.addTestClinic(
        ClinicModel(
          id: 'cln-bk-1',
          clinicName: 'Apex Smile Care Center',
          location: 'Jubilee Hills, Hyderabad',
        ),
      );
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'b-pend-1',
          patientName: 'Riya Sharma',
          patientPhone: '+919000000200',
          problemCategory: '',
          symptoms: 'IN-CLINIC',
          problemDescription: 'Molar root canal consultation',
          severity: 'Moderate',
          submittedAt: DateTime(2026, 11, 27),
          status: 'Pending',
          assignedDoctorName: 'Dr. Ananya Rao',
          assignedDoctorClinic: 'Apex Smile Care Center',
          confirmedDate: '2026-11-27',
          confirmedTimeSlot: '15:00',
        ),
      );
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'b-pend-2',
          patientName: 'Kabir Mehta',
          patientPhone: '+919888877766',
          problemCategory: 'Crown Prep',
          symptoms: 'IN-CLINIC',
          problemDescription: 'Overlapping slot check',
          severity: 'Moderate',
          submittedAt: DateTime(2026, 11, 27),
          status: 'Pending',
          assignedDoctorName: 'Dr. Ananya Rao',
          assignedDoctorClinic: 'Apex Smile Care Center',
          confirmedDate: '2026-11-27',
          confirmedTimeSlot: '15:00',
        ),
      );
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'b-canc-1',
          patientName: 'Riya Sharma',
          patientPhone: '+919000000200',
          problemCategory: '',
          symptoms: 'AUDIO CALL',
          problemDescription: 'Post-procedure follow up',
          severity: 'Mild',
          submittedAt: DateTime(2026, 8, 27),
          status: 'Cancelled',
          assignedDoctorName: 'Dr. Ananya Rao',
          assignedDoctorClinic: 'Apex Smile Care Center',
          confirmedDate: '2026-08-27',
          confirmedTimeSlot: '11:00',
        ),
      );

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: RepaintBoundary(
              key: boundaryKey,
              child: const ClinicDashboardScreen(
                clinicName: 'Apex Smile Care Center',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bookings'));
      await tester.pumpAndSettle();

      expect(find.text('All visits at your clinic'), findsOneWidget);
      expect(find.text('Bookings'), findsWidgets);
      expect(find.text('Overlapping Slot Alert Detected'), findsOneWidget);
      expect(
        find.byKey(const Key('clinic_bookings_filter_All')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('clinic_bookings_filter_Pending')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('clinic_bookings_filter_Confirmed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('clinic_bookings_filter_Completed')),
        findsOneWidget,
      );

      await _capturePng(
        tester,
        boundaryKey,
        'gs_health_clinic_bookings.png',
      );

      // Confirm b-pend-1
      await tester.tap(
        find.byKey(const Key('clinic_booking_confirm_b-pend-1')),
      );
      await tester.pumpAndSettle();

      expect(
        service.requests.firstWhere((r) => r.id == 'b-pend-1').status,
        equals('Confirmed'),
      );

      // Filter by Confirmed -> b-pend-1 visible, Kabir Pending hidden
      await tester.tap(
        find.byKey(const Key('clinic_bookings_filter_Confirmed')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clinic_booking_card_b-pend-1')), findsOneWidget);
      expect(find.byKey(const Key('clinic_booking_card_b-pend-2')), findsNothing);

      // Back to Pending -> cancel b-pend-2 with confirmation dialog
      await tester.tap(find.byKey(const Key('clinic_bookings_filter_Pending')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clinic_booking_cancel_b-pend-2')));
      await tester.pumpAndSettle();
      expect(find.text('Cancel Booking'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cancel_clinic_booking_reason_field')),
        'Doctor unavailable',
      );
      await tester.tap(
        find.byKey(const Key('confirm_cancel_clinic_booking_button')),
      );
      await tester.pumpAndSettle();

      expect(
        service.requests.firstWhere((r) => r.id == 'b-pend-2').status,
        equals('Cancelled'),
      );
    },
  );

  testWidgets(
    '5. Zero RenderFlex overflow across 320, 360, 390, and 412 widths on Clinic Dashboard',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      addTearDown(tester.view.reset);

      final service = PatientProblemService();
      service.addTestClinic(
        ClinicModel(
          id: 'cln-resp',
          clinicName: 'Very Long Multi-Specialty Dental & Implant Healthcare Clinic',
          location: 'Plot 42, Jubilee Hills Main Road, Hyderabad - 500033',
          isFeatured: true,
        ),
      );
      service.addTestDoctor(
        DoctorModel(
          id: 'doc-resp-1',
          name: 'Dr. Rajeshwari Venkatasubramanian',
          specialty: 'Oral & Maxillofacial Surgery',
          qualification: 'BDS, MDS, FDSRCS',
          experienceYears: 14,
          rating: 4.9,
          reviewCount: 60,
          clinicName:
              'Very Long Multi-Specialty Dental & Implant Healthcare Clinic',
          phone: '9800012345',
          email: 'raji@clinic.com',
          status: 'Available',
          nextAvailableSlots: const ['10:00 AM'],
          consultationFee: '₹800',
        ),
      );
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'bk-resp-1',
          patientName: 'Srinivasan Venkataramanan',
          patientPhone: '+919988776655',
          problemCategory: 'IN-CLINIC · Surgery',
          problemDescription: 'Impacted third molar evaluation',
          severity: 'Moderate',
          submittedAt: DateTime(2026, 11, 27),
          status: 'Pending',
          assignedDoctorName: 'Dr. Rajeshwari Venkatasubramanian',
          assignedDoctorClinic:
              'Very Long Multi-Specialty Dental & Implant Healthcare Clinic',
          confirmedDate: '2026-11-27',
          confirmedTimeSlot: '10:30 AM',
        ),
      );

      for (final width in [320.0, 360.0, 390.0, 412.0]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey('clinic_scope_$width'),
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const ClinicDashboardScreen(
                clinicName:
                    'Very Long Multi-Specialty Dental & Implant Healthcare Clinic',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Bookings'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
