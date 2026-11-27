import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/constants/permissions.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:dentaguru/features/admin/presentation/screens/sub_admin_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiService.debugCreateSubAdminOverride = null;
    ApiService.debugUpdateSubAdminOverride = null;
    ApiService.debugFetchSubAdminsOverride = null;
    ApiService.debugToggleSubAdminStatusOverride = null;
    PatientProblemService().clearSubAdminSession();
  });

  tearDown(() {
    ApiService.debugCreateSubAdminOverride = null;
    ApiService.debugUpdateSubAdminOverride = null;
    ApiService.debugFetchSubAdminsOverride = null;
    ApiService.debugToggleSubAdminStatusOverride = null;
    PatientProblemService().clearSubAdminSession();
  });

  testWidgets(
    'Admin Dashboard Create Sub-Admin modal validates required fields, handles duplicate errors without closing modal, and creates Sub-Admin',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final List<Map<String, dynamic>> createdSubAdmins = [];

      ApiService.debugFetchSubAdminsOverride = () async => List<dynamic>.from(createdSubAdmins);

      ApiService.debugCreateSubAdminOverride = ({
        required String name,
        required String phone,
        String? email,
        String? password,
        String? city,
        String? pincode,
        List<String>? languages,
        List<String>? permissions,
        List<String>? districtIds,
        String status = 'ACTIVE',
        String? profilePhoto,
      }) async {
        final existsPhone = createdSubAdmins.any((s) => s['phone'] == phone);
        if (existsPhone) {
          return {
            'success': false,
            'code': 'MOBILE_ALREADY_REGISTERED',
            'message': 'Phone number already registered.',
          };
        }
        final newSa = {
          'id': 'sa-${createdSubAdmins.length + 1}',
          'name': name,
          'phone': phone,
          'email': email ?? 'user_$phone@dentaguru.internal',
          'role': 'Sub-Admin',
          'status': status,
          'city': city ?? '',
          'pincode': pincode ?? '',
          'languages': languages ?? ['English'],
          'permissions': permissions ?? ['PATIENT_VIEW'],
          'assignedDistricts': [],
        };
        createdSubAdmins.add(newSa);
        return {
          'success': true,
          'message': 'Sub-Admin created successfully.',
          'subAdmin': newSa,
        };
      };

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AdminDashboardScreen(initialTab: 9),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Open Create Coordinator modal
      final createBtn = find.text('+ Create Coordinator');
      expect(createBtn, findsOneWidget);
      await tester.tap(createBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('create_sub_admin_dialog')), findsOneWidget);
      expect(find.byKey(const Key('subadmin_create_role_field')), findsOneWidget);
      expect(find.text('Role: Coordinator'), findsOneWidget);

      // 1. Validate empty Full Name
      final submitBtn = find.byKey(const Key('subadmin_create_submit_btn'));
      await tester.tap(submitBtn);
      await tester.pump();
      expect(find.byKey(const Key('subadmin_create_error_banner')), findsOneWidget);
      expect(find.textContaining('Full Name'), findsWidgets);

      // 2. Validate 10-digit Mobile Phone Number
      await tester.enterText(find.byKey(const Key('subadmin_create_name_field')), 'Kiran Kumar');
      await tester.enterText(find.byKey(const Key('subadmin_create_phone_field')), '98765');
      await tester.tap(submitBtn);
      await tester.pump();
      expect(find.textContaining('10-digit Mobile Phone Number'), findsWidgets);

      // 3. Fill valid details and select Doctors permission in addition to default Patient View
      await tester.enterText(find.byKey(const Key('subadmin_create_phone_field')), '9876543210');
      await tester.enterText(find.byKey(const Key('subadmin_create_email_field')), 'kiran@gshealth.com');
      await tester.enterText(find.byKey(const Key('subadmin_create_password_field')), 'Secret123');

      final docPermCheckbox = find.byKey(const Key('subadmin_perm_checkbox_DENTIST_VIEW'));
      await tester.ensureVisible(docPermCheckbox);
      await tester.tap(docPermCheckbox);
      await tester.pump();

      await tester.tap(submitBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Modal should close on success and newly created Sub-Admin should appear in listing
      expect(find.byKey(const Key('create_sub_admin_dialog')), findsNothing);
      expect(createdSubAdmins.length, 1);
      expect(createdSubAdmins.first['name'], 'Kiran Kumar');
      expect(createdSubAdmins.first['role'], 'Sub-Admin');
      expect(createdSubAdmins.first['permissions'], containsAll(['PATIENT_VIEW', 'DENTIST_VIEW']));
      expect(find.text('Kiran Kumar'), findsWidgets);

      // 4. Re-open modal and verify duplicate mobile number keeps modal open and shows error banner
      await tester.tap(createBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(const Key('subadmin_create_name_field')), 'Duplicate Kiran');
      await tester.enterText(find.byKey(const Key('subadmin_create_phone_field')), '9876543210');
      await tester.tap(find.byKey(const Key('subadmin_create_submit_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('create_sub_admin_dialog')), findsOneWidget);
      expect(find.byKey(const Key('subadmin_create_error_banner')), findsOneWidget);
      expect(find.textContaining('Phone number already registered'), findsWidgets);
    },
  );

  testWidgets(
    'Sub-Admin Dashboard displays only authorized modules based on assigned permissions',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Grant ONLY PATIENT_VIEW and REPORT_VIEW
      PatientProblemService().setSubAdminSession(
        id: 'sa-perm-test-1',
        name: 'Restricted Sub-Admin',
        email: 'restricted@gshealth.com',
        phone: '9111222333',
        permissions: [AppPermissions.patientView, AppPermissions.reportView],
        status: 'ACTIVE',
      );

      expect(PatientProblemService().hasPermission(AppPermissions.patientView), isTrue);
      expect(PatientProblemService().hasPermission(AppPermissions.reportView), isTrue);
      expect(PatientProblemService().hasPermission(AppPermissions.dentistView), isFalse);
      expect(PatientProblemService().hasPermission(AppPermissions.appointmentView), isFalse);
      expect(PatientProblemService().hasPermission(AppPermissions.assignmentCreate), isFalse);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SubAdminDashboardScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Coordinator Dashboard'), findsOneWidget);
      expect(find.text('Overview & Reports'), findsWidgets);
      // Unpermitted tabs like Appointments and Doctor Assignments should not be in the module tab bar
      expect(find.text('Doctor Assignments'), findsNothing);
    },
  );
}
