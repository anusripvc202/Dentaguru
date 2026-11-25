import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchAppointmentsOverride = null;
    await SessionService().clearSession();
    final service = PatientProblemService();
    await service.clearAllData();
  });

  tearDown(() async {
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchAppointmentsOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  group('Admin Dashboard – Deduplication & Zero Dummy Data Verification', () {
    testWidgets(
      '1. Deduplicates doctors, patients, clinics, and appointments; shows exact unique counts & zero dummy ads on Overview (desktop + mobile)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();

        // Seed duplicate doctors (same id / phone)
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-1',
            userId: 'u-doc-1',
            name: 'Dr. Rohitha',
            specialty: 'Dermatology',
            qualification: 'MBBS, MD',
            experienceYears: 6,
            rating: 4.9,
            reviewCount: 12,
            clinicName: 'Devi Clinic',
            phone: '8986754323',
            email: 'rohitha@gshealth.test',
            status: 'Available',
            nextAvailableSlots: const ['10:00 AM'],
            consultationFee: '₹600',
          ),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-1',
            userId: 'u-doc-1',
            name: 'Dr. Rohitha',
            specialty: 'Dermatology',
            qualification: 'MBBS, MD',
            experienceYears: 6,
            rating: 4.9,
            reviewCount: 12,
            clinicName: 'Devi Clinic',
            phone: '8986754323',
            email: 'rohitha@gshealth.test',
            status: 'Available',
            nextAvailableSlots: const ['10:00 AM'],
            consultationFee: '₹600',
          ),
        );

        // Seed duplicate patients + a doctor accidentally in patients list
        service.addTestPatient(
          PatientProfile(
            id: 'pat-1',
            name: 'Anu',
            phone: '9063663180',
            email: 'anu@gshealth.test',
          ),
        );
        service.addTestPatient(
          PatientProfile(
            id: 'pat-1',
            name: 'Anu',
            phone: '9063663180',
            email: 'anu@gshealth.test',
          ),
        );
        service.addTestPatient(
          PatientProfile(
            id: 'u-doc-1', // Doctor's user_id must be excluded from patients
            name: 'Dr. Rohitha',
            phone: '8986754323',
            email: 'rohitha@gshealth.test',
          ),
        );

        // Seed duplicate clinics
        service.addTestClinic(
          ClinicModel(
            id: 'clinic-1',
            clinicName: 'Devi Clinic',
            location: 'Hyderabad',
          ),
        );
        service.addTestClinic(
          ClinicModel(
            id: 'clinic-1',
            clinicName: 'Devi Clinic',
            location: 'Hyderabad',
          ),
        );

        // Seed duplicate appointment rows (same id AND duplicate fingerprint)
        ApiService.debugAdminAppointmentsOverride = () async => [
              {
                'id': 'appt-1',
                'patient_id': 'pat-1',
                'patient_name': 'Anu',
                'dentist_id': 'doc-1',
                'dentist_name': 'Dr. Rohitha',
                'treatment': 'General Consultation',
                'status': 'CONFIRMED',
                'date': '2026-11-20T00:00:00Z',
                'time_slot': '09:30 AM',
              },
              {
                'id': 'appt-1', // exact same id duplicate
                'patient_id': 'pat-1',
                'patient_name': 'Anu',
                'dentist_id': 'doc-1',
                'dentist_name': 'Dr. Rohitha',
                'treatment': 'General Consultation',
                'status': 'CONFIRMED',
                'date': '2026-11-20T00:00:00Z',
                'time_slot': '09:30 AM',
              },
              {
                'id': 'appt-1-dup-retry', // exact duplicate booking retry fingerprint
                'patient_id': 'pat-1',
                'patient_name': 'Anu',
                'dentist_id': 'doc-1',
                'dentist_name': 'Dr. Rohitha',
                'treatment': 'General Consultation',
                'status': 'CONFIRMED',
                'date': '2026-11-20T00:00:00Z',
                'time_slot': '09:30 AM',
              },
            ];

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(useMaterial3: false),
              home: const AdminDashboardScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));

        // Exact deduplicated stat counts: 1 patient, 1 doctor, 1 clinic, 1 appointment
        expect(tester.widget<Text>(find.byKey(const Key('admin_stat_value_patients'))).data, equals('1'));
        expect(tester.widget<Text>(find.byKey(const Key('admin_stat_value_dentists'))).data, equals('1'));
        expect(tester.widget<Text>(find.byKey(const Key('admin_stat_value_clinics'))).data, equals('1'));
        expect(tester.widget<Text>(find.byKey(const Key('admin_stat_value_appointments'))).data, equals('1'));

        // Exactly 1 appointment card rendered (not 3!)
        expect(find.byKey(const Key('admin_appointment_card_0')), findsOneWidget);
        expect(find.byKey(const Key('admin_appointment_card_1')), findsNothing);

        // Zero dummy sponsored ads (no Colgate, Oral-B, Listerine, Sensodyne)
        expect(find.byKey(const Key('admin_ads_empty')), findsOneWidget);
        expect(find.text('Colgate Total'), findsNothing);
        expect(find.text('Oral-B iO Series'), findsNothing);
        expect(find.text('Listerine Cool Mint'), findsNothing);

        // Desktop does not duplicate sidebar with mobile "Console sections" footer
        expect(find.text('Console sections'), findsNothing);
      },
    );

    testWidgets(
      '2. Revenue panel is removed & Specialty Reporting / Analytics panels show zero dummy charts/percentages when DB has 0 appointments',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        ApiService.debugAdminAppointmentsOverride = () async => const [];

        // A. Revenue removed -> Tab 5 renders Specialty Reporting with zero dummy revenue cards
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(useMaterial3: false),
              home: const AdminDashboardScreen(initialTab: 5),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Specialty-Based Healthcare Analytics'), findsOneWidget);
        expect(find.text('Revenue, Financial & Specialty Analytics'), findsNothing);
        expect(find.text('Cleaning'), findsNothing);
        expect(find.text('Root Canal'), findsNothing);
        expect(find.text('Implants'), findsNothing);
        expect(find.text('35%'), findsNothing);

        // B. Requests/Analytics panel (tab 13) with 0 appointments -> NO dummy 65%/25%/10%
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(useMaterial3: false),
              home: const AdminDashboardScreen(key: ValueKey('tab13'), initialTab: 13),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('No appointments recorded yet.'), findsOneWidget);
        expect(find.text('65%'), findsNothing);
      },
    );
  });
}
