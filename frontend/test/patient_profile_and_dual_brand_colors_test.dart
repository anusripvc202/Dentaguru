import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/theme/app_theme.dart';
import 'package:dentaguru/core/widgets/denta_guru_logo.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:dentaguru/features/auth/presentation/screens/auth_screen.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ApiService.debugFetchAppointmentsOverride = ({String? patientId, String? dentistId}) async => [];
    ApiService.debugAdminAppointmentsOverride = () async => [];
    ApiService.debugFetchNotificationsOverride = ({String? role, String? userId}) async => [];
  });

  tearDown(() async {
    ApiService.debugFetchAppointmentsOverride = null;
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchNotificationsOverride = null;
    await SessionService().clearSession();
  });

  testWidgets(
    '1. Patient Dashboard Profile icon opens profile menu with horizontally centered dynamic patient name across Mobile, Tablet & Desktop',
    (tester) async {
      final service = PatientProblemService();
      await service.clearAllData();

      // Case A: Dynamic PatientProfile loaded for logged-in user
      service.updatePatientProfile(
        id: 'pat-rohan-001',
        name: 'Rohan Deshmukh',
        email: 'rohan@gshealth.test',
        phone: '9876543210',
        age: '31',
        gender: 'Male',
        bloodGroup: 'B+',
        emergencyContact: '9876543210',
        city: 'Pune',
        pincode: '411001',
      );

      for (final viewport in const [
        Size(390, 844), // Mobile
        Size(768, 1024), // Tablet
        Size(1280, 900), // Desktop
      ]) {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const PatientDashboardScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        final avatarBtn = find.byKey(const Key('dashboard_profile_avatar_button'));
        expect(avatarBtn, findsOneWidget);
        await tester.tap(avatarBtn);
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byKey(const Key('patient_profile_card')), findsOneWidget);
        final nameFinder = find.byKey(const Key('profile_patient_display_name'));
        expect(nameFinder, findsOneWidget);

        final Text nameText = tester.widget<Text>(nameFinder);
        expect(nameText.data, 'Rohan Deshmukh');
        expect(nameText.textAlign, TextAlign.center);

        // Verify true horizontal centering inside patient_profile_card
        final cardBox = tester.getRect(find.byKey(const Key('patient_profile_card')));
        final nameBox = tester.getRect(nameFinder);
        expect((nameBox.center.dx - cardBox.center.dx).abs(), lessThanOrEqualTo(2.0));

        // Verify zero hardcoded fallback names appear
        expect(find.text('Anu'), findsNothing);
        expect(find.text('anusha'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }

      // Case B: SessionService dynamic fallback when PatientProfile has default 'Patient' name
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.clearAllData();
      await SessionService().saveSession(
        token: 'tok-meera',
        role: 'Patient',
        userId: 'pat-meera-002',
        phone: '9988776655',
        name: 'Meera Nair',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PatientDashboardScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byKey(const Key('dashboard_profile_avatar_button')));
      await tester.pump(const Duration(milliseconds: 500));

      final sessionNameFinder = find.byKey(const Key('profile_patient_display_name'));
      expect(sessionNameFinder, findsOneWidget);
      expect(tester.widget<Text>(sessionNameFinder).data, 'Meera Nair');
      expect(find.text('Anu'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  test('2. AppTheme preserves exact two GS HEALTH logo colors without off-brand colors', () {
    expect(AppTheme.gsNavy, const Color(0xFF012A58));
    expect(AppTheme.gsRed, const Color(0xFFFE3434));
    expect(AppTheme.primaryBlue, AppTheme.gsNavy);
    expect(AppTheme.brandOrange, AppTheme.gsRed);
    expect(AppTheme.statusCancelText, AppTheme.gsRed);
    expect(AppTheme.lightTheme.colorScheme.primary, AppTheme.gsNavy);
    expect(AppTheme.lightTheme.colorScheme.secondary, AppTheme.gsRed);
    expect(AppTheme.darkTheme.colorScheme.primary, AppTheme.gsNavy);
    expect(AppTheme.darkTheme.colorScheme.secondary, AppTheme.gsRed);
  });

  testWidgets(
    '3. Logo & Core Dashboards (Login, Doctor, Admin) render consistently with zero overflows',
    (tester) async {
      // A. Logo widget renders cleanly
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GsHealthLogo(height: 44),
                  SizedBox(height: 16),
                  DentaGuruToothIcon(size: 48),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(GsHealthLogo), findsOneWidget);
      expect(find.byType(DentaGuruToothIcon), findsOneWidget);
      expect(tester.takeException(), isNull);

      // B. AuthScreen (Login)
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const AuthScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // C. DentistTimelineScreen
      final service = PatientProblemService();
      await service.clearAllData();
      service.setDentistMode(true);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const DentistTimelineScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DentistTimelineScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // D. AdminDashboardScreen (Desktop 1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      service.setAdminMode(true);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const AdminDashboardScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(AdminDashboardScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
