import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/models/user_session.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/sub_admin_dashboard.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_sub_admin_district_dialog.dart';
import 'package:dentaguru/features/clinic/presentation/widgets/clinic_add_doctors_dialog.dart';
import 'package:dentaguru/features/clinic/presentation/widgets/gs_health_clinic_views.dart';
import 'package:dentaguru/features/patient/presentation/screens/doctor_profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PatientProblemService().clearAllData();
  });

  test('DoctorModel.resolveFullName combines first, middle, last names and never duplicates Dr.', () {
    final docFromParts = DoctorModel.fromJson({
      'id': 'doc-parts-1',
      'first_name': 'Venkata',
      'middle_name': 'Subramanya',
      'last_name': 'Narayana Sharma',
      'speciality': 'Cardiology',
    });
    expect(docFromParts.name, 'Dr. Venkata Subramanya Narayana Sharma');
    expect(docFromParts.displayFullName, 'Dr. Venkata Subramanya Narayana Sharma');

    final docFromUsersList = DoctorModel.fromJson({
      'id': 'doc-list-2',
      'users': [
        {'id': 'u-2', 'name': 'Dr. Dr. Lakshmi Prasanna Kumari'}
      ],
      'specialty': 'General Dentistry',
    });
    expect(docFromUsersList.displayFullName, 'Dr. Lakshmi Prasanna Kumari');
  });

  test('UserSession maps Sub-Admin and Coordinator roles to Coordinator display title & /sub-admin route', () {
    final legacySubAdmin = UserSession(
      token: 'tok-1',
      userId: 'u-sa-1',
      role: 'Sub-Admin',
      createdAt: DateTime.now(),
    );
    expect(legacySubAdmin.displayRole, 'Coordinator');
    expect(legacySubAdmin.targetRoute, '/sub-admin');

    final coordinatorAlias = UserSession(
      token: 'tok-2',
      userId: 'u-sa-2',
      role: 'Coordinator',
      createdAt: DateTime.now(),
    );
    expect(coordinatorAlias.displayRole, 'Coordinator');
    expect(coordinatorAlias.targetRoute, '/sub-admin');
  });

  testWidgets('Clinic Overview, Add Existing Doctor, and Doctor Details display complete doctor full name without single-line cut-off', (tester) async {
    const fullName = 'Dr. Venkata Subramanya Narayana Sharma';
    final doc = DoctorModel(
      id: 'doc-full-1',
      userId: 'usr-full-1',
      clinicId: 'clinic-1',
      name: fullName,
      specialty: 'Cardiology',
      qualification: 'MBBS, MD, DM',
      experienceYears: 14,
      rating: 4.9,
      reviewCount: 25,
      clinicName: 'GS Heart Specialty Clinic',
      phone: '9876543210',
      email: 'venkata@gshealth.in',
      status: 'Available',
      nextAvailableSlots: const ['10:00 AM', '10:30 AM'],
      consultationFee: '₹500',
    );

    // 1. Clinic Overview card on narrow mobile viewport (360px)
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GsHealthClinicOverview(
              clinicName: 'GS Heart Specialty Clinic',
              clinicLocation: 'Hyderabad, Telangana',
              coverImageUrl: '',
              isFeatured: false,
              featuredPlan: '',
              unreadNotifications: 0,
              referralsCount: 0,
              visitsTodayCount: 0,
              awaitingConfirmationCount: 0,
              completedVisitsCount: 0,
              attachedDoctors: [doc],
              onNotifications: () {},
              onProfile: () {},
              onEditDetails: () {},
              onOpenFeaturedPlan: () {},
              onOpenReferrals: () {},
              onOpenAdvertise: () {},
              onTapBookingsStat: (_) {},
              onAddDoctor: () {},
              onRefresh: () async {},
              onToggleDoctorStatus: (_) {},
              onViewDoctorProfile: (_) {},
              onEditDoctor: (_) {},
              onManageDoctorSlots: (_) {},
              onRemoveDoctor: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final overviewNameText = tester.widget<Text>(find.byKey(const Key('clinic_doctor_name_doc-full-1')));
    expect(overviewNameText.data, fullName);
    expect(overviewNameText.softWrap, isTrue);
    expect(overviewNameText.maxLines, isNull);

    // 2. Add Existing Doctor dialog shows complete doctor full name with wrapping
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ClinicAddDoctorsDialog(
              clinicId: 'clinic-1',
              clinicName: 'GS Heart Specialty Clinic',
              allRegisteredDoctors: [doc],
              alreadyAssociatedDoctorIds: const {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final addDialogNameText = tester.widget<Text>(find.byKey(const Key('clinic_add_doctor_name_doc-full-1')));
    expect(addDialogNameText.data, fullName);
    expect(addDialogNameText.softWrap, isTrue);
    expect(addDialogNameText.maxLines, isNull);

    // 3. Doctor Profile Details screen shows complete doctor full name with wrapping
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DoctorProfileScreen(
            doctor: doc,
            isClinicView: true,
          ),
        ),
      ),
    );
    await tester.pump();

    final profileNameText = tester.widget<Text>(find.byKey(const Key('doctor_profile_full_name_doc-full-1')));
    expect(profileNameText.data, fullName);
    expect(profileNameText.softWrap, isTrue);
    expect(profileNameText.maxLines, isNull);
  });

  testWidgets('Coordinator Dashboard & Assigned District dialog display Coordinator terminology without Sub-Admin labels', (tester) async {
    final svc = PatientProblemService();
    svc.setSubAdminSession(
      id: 'coord-1',
      name: 'Kiran Coordinator',
      email: 'kiran@gshealth.in',
      phone: '9988776655',
      permissions: const ['PATIENT_VIEW'],
      assignedDistricts: const [
        {'id': 'dist-hyd', 'name': 'Hyderabad', 'state': 'Telangana'},
      ],
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SubAdminDashboardScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Coordinator Dashboard'), findsOneWidget);
    expect(find.textContaining('Assigned District'), findsWidgets);
    expect(find.textContaining('Sub-Admin'), findsNothing);

    // Verify Assigned District dialog labels
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GsHealthSubAdminDistrictDialog(
              subAdmin: const {
                'id': 'coord-1',
                'name': 'Kiran Coordinator',
                'assignedDistricts': [
                  {'id': 'dist-hyd', 'name': 'Hyderabad', 'state': 'Telangana'}
                ],
              },
              problemService: svc,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Assigned District'), findsOneWidget);
    expect(find.textContaining('Coordinator'), findsWidgets);
    expect(find.textContaining('Sub-Admin'), findsNothing);
  });
}
