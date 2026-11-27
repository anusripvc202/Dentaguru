import 'dart:io';
import 'dart:ui' as ui;

import 'package:dentaguru/core/constants/permissions.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:dentaguru/features/admin/presentation/screens/sub_admin_dashboard.dart';
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
      final boldBytes =
          boldFile.existsSync() ? boldFile.readAsBytesSync() : regBytes;
      final semiBytes =
          semiboldFile.existsSync() ? semiboldFile.readAsBytesSync() : boldBytes;

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
            ..addFont(Future.value(ByteData.view(Uint8List.fromList(iconBytes).buffer)));
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
      try {
        await precacheImage(widget.image, element);
      } catch (_) {}
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
      await File(outputPath).writeAsBytes(byteData.buffer.asUint8List());
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
    ApiService.debugAdminAppointmentsOverride = null;
    await PatientProblemService().clearAllData();
    PatientProblemService().clearSubAdminSession();
  });

  tearDown(() async {
    ApiService.debugAdminAppointmentsOverride = null;
    PatientProblemService().clearSubAdminSession();
    await PatientProblemService().clearAllData();
  });

  void seedPlatformData(PatientProblemService service) {
    service.addTestDoctor(
      DoctorModel(
        id: 'doc-ananya-rao',
        userId: 'usr-ananya',
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
        verificationStatus: 'VERIFIED',
        consultationFee: '₹600',
        city: 'Mumbai',
        pincode: '400050',
        clinicAddress: 'Hill Road, Bandra West, Mumbai',
        languages: const ['English', 'Hindi'],
        nextAvailableSlots: const ['10:00 AM', '03:00 PM'],
      ),
    );
    service.addTestDoctor(
      DoctorModel(
        id: 'doc-pending-kavita',
        userId: 'usr-kavita',
        name: 'Dr. Kavita Deshmukh',
        specialty: 'Orthodontist',
        qualification: 'BDS, MDS',
        experienceYears: 6,
        rating: 4.7,
        reviewCount: 24,
        clinicName: 'Smile Care Dadar',
        phone: '9820055667',
        email: 'kavita@gshealth.in',
        status: 'Available',
        verificationStatus: 'PENDING_VERIFICATION',
        consultationFee: '₹700',
        city: 'Mumbai',
        pincode: '400014',
        clinicAddress: 'Dadar West, Mumbai',
        languages: const ['English', 'Marathi'],
        nextAvailableSlots: const ['11:00 AM'],
      ),
    );
    service.addTestClinic(
      ClinicModel(
        id: 'clinic-bandra',
        clinicName: 'Bandra West Dental Clinic',
        location: 'Hill Road, Bandra West, Mumbai - 400050',
        services: const ['Root Canal', 'Implants'],
      ),
    );
    service.updatePatientProfile(
      id: 'pat-riya',
      name: 'Riya Sharma',
      email: 'riya@gshealth.in',
      phone: '9000000200',
      age: '34',
      gender: 'Female',
      bloodGroup: 'O+',
      emergencyContact: '9000000200',
      city: 'Mumbai',
      pincode: '400050',
    );
    service.updatePatientProfile(
      id: 'pat-amit',
      name: 'Amit Verma',
      email: 'amit@gshealth.in',
      phone: '9876543210',
      age: '29',
      gender: 'Male',
      bloodGroup: 'B+',
      emergencyContact: '9876543210',
      city: 'Mumbai',
      pincode: '400051',
    );

    // 2 waiting consultation requests awaiting a doctor
    service.addTestRequest(
      PatientConsultationRequest(
        id: 'req-wait-1',
        patientId: 'pat-riya',
        patientName: 'Riya Sharma',
        patientPhone: '+919000000200',
        problemCategory: 'Endodontist',
        problemDescription: 'Lower molar pain during cold drinks',
        severity: 'Moderate',
        status: 'Pending Admin Review',
        submittedAt: DateTime(2026, 11, 14, 9, 30),
      ),
    );
    service.addTestRequest(
      PatientConsultationRequest(
        id: 'req-wait-2',
        patientId: 'pat-amit',
        patientName: 'Amit Verma',
        patientPhone: '+919876543210',
        problemCategory: 'Orthodontist',
        problemDescription: 'Braces wire alignment checkup',
        severity: 'Low',
        status: 'Pending Admin Review',
        submittedAt: DateTime(2026, 11, 14, 10, 15),
      ),
    );

    // 2 unread notifications for Admin / Sub-Admin
    service.addNotification(
      recipientRole: 'Admin',
      recipientId: 'ALL_ADMINS',
      title: 'Verification Pending',
      message: 'Dr. Kavita Deshmukh uploaded registration documents.',
    );
    service.addNotification(
      recipientRole: 'Sub-Admin',
      recipientId: 'ALL_ADMINS',
      title: 'New Triage Request',
      message: 'Riya Sharma submitted a consultation request.',
    );
  }

  List<Map<String, dynamic>> sampleAppointments({int count = 3}) {
    final rows = <Map<String, dynamic>>[
      {
        'id': 'appt-1',
        'patient_name': 'Riya Sharma',
        'patient_phone': '+919000000200',
        'dentist_name': 'Dr. Ananya Rao',
        'clinic_name': 'Bandra West Dental Clinic',
        'date': '2026-11-27',
        'time_slot': '03:00 PM',
        'status': 'Pending',
        'mode': 'IN-CLINIC',
        'treatment': 'Endodontic consultation',
        'notes': 'Sensitive lower right molar',
      },
      {
        'id': 'appt-2',
        'patient_name': 'Riya Sharma',
        'patient_phone': '+919000000200',
        'dentist_name': 'Dr. Ananya Rao',
        'clinic_name': 'Bandra West Dental Clinic',
        'date': '2026-08-27',
        'time_slot': '11:00 AM',
        'status': 'Cancelled',
        'mode': 'IN-CLINIC',
        'treatment': 'Follow-up checkup',
      },
      {
        'id': 'appt-3',
        'patient_name': 'Amit Verma',
        'patient_phone': '+919876543210',
        'dentist_name': 'Dr. Kavita Deshmukh',
        'clinic_name': 'Smile Care Dadar',
        'date': '2026-11-28',
        'time_slot': '10:30 AM',
        'status': 'Confirmed',
        'mode': 'ONLINE',
        'treatment': 'Orthodontic alignment',
        'notes': 'Initial tele-consultation',
      },
    ];
    if (count <= rows.length) return rows.sublist(0, count);
    final out = List<Map<String, dynamic>>.from(rows);
    for (int i = rows.length + 1; i <= count; i++) {
      out.add({
        'id': 'appt-$i',
        'patient_name': 'Patient #$i',
        'patient_phone': '+9198000000${i.toString().padLeft(2, '0')}',
        'dentist_name': 'Dr. Ananya Rao',
        'clinic_name': 'Bandra West Dental Clinic',
        'date': '2026-11-29',
        'time_slot': '04:00 PM',
        'status': 'Confirmed',
        'mode': 'IN-CLINIC',
        'treatment': 'Dental Checkup',
      });
    }
    return out;
  }

  testWidgets('Admin Dashboard redesign renders GS HEALTH Overview, interactions & captures top/bottom PNGs', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = PatientProblemService();
    seedPlatformData(service);
    ApiService.debugAdminAppointmentsOverride = () async => sampleAppointments(count: 12);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RepaintBoundary(
            key: boundaryKey,
            child: const AdminDashboardScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Admin console'), findsOneWidget);
    expect(find.text('GS HEALTH'), findsWidgets);
    expect(find.text('Requests awaiting a doctor'), findsOneWidget);
    expect(find.text('Doctors pending verification'), findsOneWidget);
    expect(find.text('Patients'), findsWidgets);
    expect(find.text('Doctors'), findsWidgets);
    expect(find.text('Clinics'), findsWidgets);
    expect(find.text('Appointments'), findsWidgets);
    expect(find.text('Assign 2 waiting request(s)'), findsOneWidget);
    expect(find.byKey(const Key('admin_action_clinics_owners')), findsOneWidget);
    expect(find.byKey(const Key('admin_action_referrals')), findsOneWidget);
    expect(find.byKey(const Key('admin_action_sponsored_ads')), findsOneWidget);
    expect(find.text('Clinics & owners'), findsOneWidget);
    expect(find.text('Referrals'), findsWidgets);
    expect(find.text('Sponsored ads'), findsOneWidget);

    await _capturePngIfPossible(tester, boundaryKey, '$artifactDir/gs_health_admin_top.png');

    // Scroll Overview down to capture SMS login, Sponsored carousel, and Latest appointments
    final scrollFinder = find.byKey(const Key('admin_overview_scroll'));
    await tester.drag(scrollFinder, const Offset(0, -680));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('SMS login'), findsOneWidget);
    expect(find.text('Latest appointments'), findsOneWidget);
    expect(find.text('SPONSORED'), findsNothing);
    expect(find.text('IN-CLINIC'), findsWidgets);
    expect(find.byKey(const Key('admin_appointments_load_more')), findsOneWidget);
    expect(find.text('Load more (2 remaining)'), findsOneWidget);

    await _capturePngIfPossible(tester, boundaryKey, '$artifactDir/gs_health_admin_bottom.png');

    // Pagination expands remaining 2 appointments
    await tester.ensureVisible(find.byKey(const Key('admin_appointments_load_more')));
    await tester.tap(find.byKey(const Key('admin_appointments_load_more')));
    await tester.pump();
    expect(find.byKey(const Key('admin_appointment_card_11')), findsOneWidget);

    // Appointment details sheet opens on tap
    await tester.ensureVisible(find.byKey(const Key('admin_appointment_card_0')));
    await tester.tap(find.byKey(const Key('admin_appointment_card_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Open appointments schedule'), findsOneWidget);
    Navigator.of(tester.element(find.text('Open appointments schedule'))).pop();
    await tester.pump();

    // Quick actions open read-only sheets cleanly
    await tester.drag(scrollFinder, const Offset(0, 700));
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin_action_sponsored_ads')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('read-only here'), findsOneWidget);
    Navigator.of(tester.element(find.textContaining('read-only here'))).pop();
    await tester.pump();

    await tester.tap(find.byKey(const Key('admin_action_sms_login')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Sign-in method'), findsOneWidget);
    Navigator.of(tester.element(find.text('Sign-in method'))).pop();
    await tester.pump();

    // Tapping Dentists pending verification navigates to Dentists panel with pending filter
    await tester.ensureVisible(find.byKey(const Key('admin_stat_pending_doctors')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin_stat_pending_doctors')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const Key('admin_pending_verification_panel')), findsOneWidget);
    expect(find.text('Dr. Kavita Deshmukh'), findsWidgets);
  });

  testWidgets('Sub-Admin Dashboard enforces RBAC restrictions, phone privacy & captures top/bottom PNGs', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = PatientProblemService();
    seedPlatformData(service);
    service.setSubAdminSession(
      id: 'sub-1',
      name: 'Neha Kulkarni',
      email: 'neha.ops@gshealth.in',
      phone: '9820012345',
      permissions: const [
        AppPermissions.assignmentView,
        AppPermissions.assignmentCreate,
        AppPermissions.patientView,
      ],
    );
    ApiService.debugAdminAppointmentsOverride = () async => sampleAppointments(count: 2);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RepaintBoundary(
            key: boundaryKey,
            child: const SubAdminDashboardScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Coordinator Dashboard'), findsOneWidget);
    expect(find.text('Assign 2 waiting request(s)'), findsOneWidget);

    await _capturePngIfPossible(tester, boundaryKey, '$artifactDir/gs_health_sub_admin_top.png');

    // Restricted stat cards display lock placeholder rather than leaking restricted data
    expect(find.text('—'), findsAtLeastNWidgets(4));

    final scrollFinder = find.byKey(const Key('admin_overview_scroll'));
    await tester.drag(scrollFinder, const Offset(0, -680));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Appointments must be restricted since Sub-Admin lacks appointmentView permission
    expect(find.byKey(const Key('admin_appointments_restricted')), findsOneWidget);
    expect(find.text('Your role does not include viewing appointments.'), findsOneWidget);

    await _capturePngIfPossible(tester, boundaryKey, '$artifactDir/gs_health_sub_admin_bottom.png');

    // Tapping restricted Doctors bottom nav tab shows access restriction snackbar
    await tester.tap(find.text('Doctors').last);
    await tester.pump();
    expect(find.textContaining('Access restricted'), findsOneWidget);
  });

  testWidgets('Sub-Admin with zero permissions renders restricted state with no unrestricted metrics', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = PatientProblemService();
    seedPlatformData(service);
    service.setSubAdminSession(
      id: 'sub-empty',
      name: 'Restricted Staff',
      email: 'restricted@gshealth.in',
      phone: '9800000001',
      permissions: const [],
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SubAdminDashboardScreen()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('No Modules Assigned'), findsOneWidget);
    expect(find.byKey(const Key('admin_stats_grid')), findsNothing);
  });

  testWidgets('Sub-Admin with appointmentView but no patientView hides patient phone numbers', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final service = PatientProblemService();
    seedPlatformData(service);
    service.setSubAdminSession(
      id: 'sub-appts',
      name: 'Schedule Coord',
      email: 'schedule@gshealth.in',
      phone: '9800000002',
      permissions: const [
        AppPermissions.appointmentView,
      ],
    );
    ApiService.debugAdminAppointmentsOverride = () async => sampleAppointments(count: 1);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SubAdminDashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Riya Sharma'), findsOneWidget);
    expect(find.textContaining('9000000200'), findsNothing);
    expect(find.text('Doctor assignment restricted'), findsOneWidget);
  });

  testWidgets('Admin Overview handles backend errors with Retry and recovers to empty appointments state', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    int attempts = 0;
    ApiService.debugAdminAppointmentsOverride = () async {
      attempts++;
      if (attempts == 1) {
        throw Exception('Appointments request failed (503).');
      }
      return const [];
    };

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AdminDashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('admin_overview_error_banner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin_overview_retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('admin_overview_error_banner')), findsNothing);
    expect(find.byKey(const Key('admin_appointments_empty')), findsOneWidget);
    expect(find.text('No appointments yet.'), findsOneWidget);
  });

  testWidgets('Admin and Sub-Admin Dashboards stay overflow-free across 320, 360, 390, and 412 widths', (tester) async {
    final service = PatientProblemService();
    seedPlatformData(service);
    ApiService.debugAdminAppointmentsOverride = () async => sampleAppointments(count: 2);

    for (final width in [320.0, 360.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AdminDashboardScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'Admin overflow at $width px');

      service.setSubAdminSession(
        id: 'sub-resp',
        name: 'Resp Checker',
        email: 'resp@gshealth.in',
        phone: '9800000009',
        permissions: const [
          AppPermissions.assignmentView,
          AppPermissions.appointmentView,
        ],
      );
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SubAdminDashboardScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'Sub-Admin overflow at $width px');
    }
    tester.view.reset();
  });
}
