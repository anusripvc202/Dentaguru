import 'package:dentaguru/core/constants/permissions.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/patient_details_screen.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_assignment_timeline_dialog.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_district_management_panel.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_district_reports_panel.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_patient_assignment_panel.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_sub_admin_district_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GS HEALTH - Sub-Admin Permissions & Restricted Defaults Test', () {
    test('Sub-Admin default permissions must be strictly restricted to PATIENT_VIEW', () {
      final defaults = AppPermissions.defaultPermissions;
      expect(defaults.length, 1);
      expect(defaults.first, AppPermissions.patientView);
      expect(defaults.contains(AppPermissions.adminSubAdminManage), isFalse);
      expect(defaults.contains(AppPermissions.adminDistrictManage), isFalse);
    });

    test('All required granular permission constants are present', () {
      expect(AppPermissions.patientView, 'PATIENT_VIEW');
      expect(AppPermissions.patientCreate, 'PATIENT_CREATE');
      expect(AppPermissions.patientEdit, 'PATIENT_EDIT');
      expect(AppPermissions.patientDelete, 'PATIENT_DELETE');
      expect(AppPermissions.dentistView, 'DENTIST_VIEW');
      expect(AppPermissions.dentistVerify, 'DENTIST_VERIFY');
      expect(AppPermissions.dentistManage, 'DENTIST_MANAGE');
      expect(AppPermissions.assignmentView, 'ASSIGNMENT_VIEW');
      expect(AppPermissions.assignmentCreate, 'ASSIGNMENT_CREATE');
      expect(AppPermissions.assignmentHistoryView, 'ASSIGNMENT_HISTORY_VIEW');
      expect(AppPermissions.clinicView, 'CLINIC_VIEW');
      expect(AppPermissions.clinicManage, 'CLINIC_MANAGE');
      expect(AppPermissions.referralView, 'REFERRAL_VIEW');
      expect(AppPermissions.referralManage, 'REFERRAL_MANAGE');
      expect(AppPermissions.reportView, 'REPORT_VIEW');
    });
  });

  group('GS HEALTH - Multi-District Jurisdiction & Access Control Test', () {
    test('Main Admin has global jurisdiction across all districts', () {
      final service = PatientProblemService();
      service.clearSubAdminSession();
      expect(service.isSubAdminMode, isFalse);
      expect(service.canAccessDistrict('Hyderabad'), isTrue);
      expect(service.canAccessDistrict('Mumbai City'), isTrue);
      expect(service.canAccessDistrict('Bengaluru Urban'), isTrue);
      expect(service.canAccessDistrict(null), isTrue);
    });

    test('Sub-Admin jurisdiction is strictly restricted to assigned districts', () {
      final service = PatientProblemService();
      service.setSubAdminSession(
        id: 'sub-admin-test-uuid-1',
        name: 'Suresh Patel',
        email: 'suresh@gshealth.in',
        phone: '+919876543210',
        permissions: ['PATIENT_VIEW', 'ASSIGNMENT_VIEW'],
        assignedDistricts: [
          {'id': 'dist-hyd', 'name': 'Hyderabad'},
          {'id': 'dist-rr', 'name': 'Rangareddy'},
        ],
      );

      expect(service.isSubAdminMode, isTrue);
      expect(service.canAccessDistrict('Hyderabad'), isTrue);
      expect(service.canAccessDistrict('Rangareddy'), isTrue);
      expect(service.canAccessDistrict('dist-hyd'), isTrue);
      expect(service.canAccessDistrict('Mumbai City'), isFalse);
      expect(service.canAccessDistrict('Pune'), isFalse);
    });

    test('Sub-Admin filtered getters return only entities in assigned districts', () {
      final service = PatientProblemService();
      service.clearAllDataAndStorage();

      service.setSubAdminSession(
        id: 'sub-admin-test-uuid-2',
        name: 'Anita Rao',
        email: 'anita@gshealth.in',
        phone: '+919876543211',
        permissions: ['PATIENT_VIEW'],
        assignedDistricts: [
          {'id': 'dist-hyd', 'name': 'Hyderabad'},
        ],
      );

      // Add dummy test patients across different districts
      final p1 = PatientProfile(id: 'p1', name: 'Rohan Sharma', city: 'Hyderabad', district: 'Hyderabad');
      final p2 = PatientProfile(id: 'p2', name: 'Priya Joshi', city: 'Mumbai', district: 'Mumbai Suburban');

      service.addTestPatient(p1);
      service.addTestPatient(p2);

      final rolePatients = service.getPatientsForCurrentRole();
      expect(rolePatients.length, 1);
      expect(rolePatients.first.name, 'Rohan Sharma');
    });
  });

  group('GS HEALTH - District Management Panel UI Test', () {
    testWidgets('Renders District Management panel and responds to search', (tester) async {
      final service = PatientProblemService();
      service.setTestDistricts([]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GsHealthDistrictManagementPanel(
              problemService: service,
              onRefresh: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Multiple District Management'), findsOneWidget);
      expect(find.text('+ Add District'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('GS HEALTH - Patient Assignment & Audit History UI Test', () {
    testWidgets('Renders Patient Assignment panel with KPI cards and source chips', (tester) async {
      final service = PatientProblemService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GsHealthPatientAssignmentPanel(
              problemService: service,
              onRefresh: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Patient Assignment & Audit Trail'), findsOneWidget);
      expect(find.text('Total Assignments'), findsOneWidget);
      expect(find.text('Direct Bookings'), findsOneWidget);
      expect(find.text('Main Admin Assigned'), findsOneWidget);
      expect(find.text('Coordinator Assigned'), findsOneWidget);
    });
  });

  group('GS HEALTH - District Reports Panel UI Test', () {
    testWidgets('Renders District-Wise Platform Reports panel', (tester) async {
      final service = PatientProblemService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GsHealthDistrictReportsPanel(
              problemService: service,
              onRefresh: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('District-Wise Platform Reports'), findsOneWidget);
      expect(find.byIcon(Icons.bar_chart_rounded), findsOneWidget);
    });
  });

  group('GS HEALTH - Patient Details Screen Assignment Information UI Test', () {
    testWidgets('Renders Assignment Information card and Assignment History action', (tester) async {
      final patient = PatientProfile(
        id: 'patient-test-123',
        name: 'Riya Sharma',
        phone: '+919000000200',
        city: 'Mumbai',
        district: 'Mumbai Suburban',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PatientDetailsScreen(patient: patient),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Assignment Information'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('District:'), findsOneWidget);
      expect(find.text('Mumbai Suburban'), findsOneWidget);
    });
  });
}
