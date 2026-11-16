import 'dart:io';
import 'dart:ui' as ui;

import 'package:dentaguru/core/constants/permissions.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:dentaguru/features/admin/presentation/screens/patient_details_screen.dart';
import 'package:dentaguru/features/admin/presentation/screens/sub_admin_dashboard.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_assignment_timeline_dialog.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_district_management_panel.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_district_reports_panel.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_patient_assignment_panel.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_sub_admin_district_dialog.dart';
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
    PatientProblemService().clearSubAdminSession();
  });

  testWidgets('Capture District Management & Assignment UI Artifacts', (tester) async {
    final service = PatientProblemService();

    // 1. Seed Real Test Districts
    service.setTestDistricts([
      {
        'id': 'dist-hyd',
        'name': 'Hyderabad',
        'state': 'Telangana',
        'code': 'HYD',
        'is_active': true,
        'assigned_sub_admins_count': 2,
        'patients_count': 14,
        'doctors_count': 5,
      },
      {
        'id': 'dist-rr',
        'name': 'Rangareddy',
        'state': 'Telangana',
        'code': 'RR',
        'is_active': true,
        'assigned_sub_admins_count': 1,
        'patients_count': 8,
        'doctors_count': 3,
      },
      {
        'id': 'dist-mum-sub',
        'name': 'Mumbai Suburban',
        'state': 'Maharashtra',
        'code': 'MUM-SUB',
        'is_active': true,
        'assigned_sub_admins_count': 3,
        'patients_count': 22,
        'doctors_count': 9,
      },
      {
        'id': 'dist-blr',
        'name': 'Bengaluru Urban',
        'state': 'Karnataka',
        'code': 'BLR-URB',
        'is_active': true,
        'assigned_sub_admins_count': 2,
        'patients_count': 19,
        'doctors_count': 7,
      },
      {
        'id': 'dist-pune',
        'name': 'Pune',
        'state': 'Maharashtra',
        'code': 'PUN',
        'is_active': false,
        'assigned_sub_admins_count': 0,
        'patients_count': 0,
        'doctors_count': 1,
      },
    ]);

    // 2. Seed Real Assignment History
    service.setTestAssignmentHistory([
      {
        'id': 'asgn-001',
        'patient_id': 'pat-101',
        'patient_name': 'Riya Sharma',
        'patient_phone': '+919000000200',
        'dentist_id': 'doc-201',
        'dentist_name': 'Dr. Rajesh Rao',
        'specialty': 'Orthodontist',
        'clinic_name': 'GS Health Dental Hub',
        'district_id': 'dist-mum-sub',
        'district_name': 'Mumbai Suburban',
        'assignment_source': 'PATIENT_DIRECT_BOOKING',
        'assignment_status': 'ACTIVE',
        'notes': 'Direct online appointment confirmed',
        'created_at': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
      },
      {
        'id': 'asgn-002',
        'patient_id': 'pat-102',
        'patient_name': 'Amit Verma',
        'patient_phone': '+919876500001',
        'dentist_id': 'doc-202',
        'dentist_name': 'Dr. Priya Desai',
        'specialty': 'Endodontist',
        'clinic_name': 'City Care Dental Clinic',
        'district_id': 'dist-hyd',
        'district_name': 'Hyderabad',
        'assignment_source': 'MAIN_ADMIN_ASSIGNMENT',
        'assigned_by_name': 'System Administrator',
        'assignment_status': 'ACTIVE',
        'notes': 'Assigned by Main Admin for urgent root canal therapy',
        'created_at': DateTime.now().subtract(const Duration(hours: 8)).toIso8601String(),
      },
      {
        'id': 'asgn-003',
        'patient_id': 'pat-103',
        'patient_name': 'Sunita Patil',
        'patient_phone': '+919876500002',
        'dentist_id': 'doc-203',
        'dentist_name': 'Dr. Ananya Roy',
        'specialty': 'General Dentist',
        'clinic_name': 'Apex Smiles',
        'district_id': 'dist-blr',
        'district_name': 'Bengaluru Urban',
        'assignment_source': 'SUB_ADMIN_ASSIGNMENT',
        'assigned_by_name': 'Kavita Reddy (Sub-Admin)',
        'assignment_status': 'REASSIGNED',
        'notes': 'Reassigned due to doctor scheduling conflict',
        'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      },
    ]);

    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // -----------------------------------------------------------------------
    // SCREENSHOT 1: District Management Panel
    // -----------------------------------------------------------------------
    final key1 = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: RepaintBoundary(
              key: key1,
              child: SingleChildScrollView(
                child: GsHealthDistrictManagementPanel(
                  problemService: service,
                  onRefresh: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _capturePngIfPossible(tester, key1, '$artifactDir\\gs_health_district_management.png');

    // -----------------------------------------------------------------------
    // SCREENSHOT 2: Sub-Admin District Assignment Dialog
    // -----------------------------------------------------------------------
    final key2 = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0x66000000),
            body: Center(
              child: RepaintBoundary(
                key: key2,
                child: GsHealthSubAdminDistrictDialog(
                  subAdmin: const {
                    'id': 'sub-admin-1',
                    'name': 'Kavita Reddy',
                    'email': 'kavita@gshealth.in',
                    'assigned_districts': [
                      {'id': 'dist-hyd', 'name': 'Hyderabad'},
                      {'id': 'dist-rr', 'name': 'Rangareddy'},
                    ],
                  },
                  problemService: service,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _capturePngIfPossible(tester, key2, '$artifactDir\\gs_health_sub_admin_district_assignment.png');

    // -----------------------------------------------------------------------
    // SCREENSHOT 3: Patient Assignment & Audit History Panel
    // -----------------------------------------------------------------------
    final key3 = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: RepaintBoundary(
              key: key3,
              child: SingleChildScrollView(
                child: GsHealthPatientAssignmentPanel(
                  problemService: service,
                  onRefresh: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _capturePngIfPossible(tester, key3, '$artifactDir\\gs_health_patient_assignment_panel.png');

    // -----------------------------------------------------------------------
    // SCREENSHOT 4: Chronological Assignment History Timeline Dialog
    // -----------------------------------------------------------------------
    final key4 = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0x66000000),
            body: Center(
              child: RepaintBoundary(
                key: key4,
                child: GsHealthAssignmentTimelineDialog(
                  patientId: 'pat-101',
                  patientName: 'Riya Sharma',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _capturePngIfPossible(tester, key4, '$artifactDir\\gs_health_assignment_timeline.png');

    // -----------------------------------------------------------------------
    // SCREENSHOT 5: Patient Details Screen with Assignment Information
    // -----------------------------------------------------------------------
    final key5 = GlobalKey();
    final patientRecord = PatientProfile(
      id: 'pat-101',
      name: 'Riya Sharma',
      phone: '+919000000200',
      city: 'Mumbai',
      district: 'Mumbai Suburban',
      districtIdentificationStatus: 'IDENTIFIED',
      languages: ['English', 'Hindi', 'Marathi'],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: RepaintBoundary(
              key: key5,
              child: PatientDetailsScreen(patient: patientRecord),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _capturePngIfPossible(tester, key5, '$artifactDir\\gs_health_patient_assignment_details.png');

    // -----------------------------------------------------------------------
    // SCREENSHOT 6: Sub-Admin Dashboard with Territory Header Banner
    // -----------------------------------------------------------------------
    service.setSubAdminSession(
      id: 'sub-admin-1',
      name: 'Kavita Reddy',
      email: 'kavita@gshealth.in',
      phone: '+919876543210',
      permissions: ['PATIENT_VIEW', 'ASSIGNMENT_VIEW', 'DENTIST_VIEW', 'REPORT_VIEW'],
      assignedDistricts: const [
        {'id': 'dist-hyd', 'name': 'Hyderabad'},
        {'id': 'dist-rr', 'name': 'Rangareddy'},
      ],
    );

    final key6 = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: RepaintBoundary(
              key: key6,
              child: const SubAdminDashboardScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _capturePngIfPossible(tester, key6, '$artifactDir\\gs_health_sub_admin_territory_dashboard.png');
  });
}
