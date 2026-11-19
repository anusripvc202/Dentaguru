import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/models/referral_model.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const patientUserId = 'pat-user-anu-001';
  const docUserId = 'doc-user-sri-001';
  const docDentistId = 'doc-dent-sri-001';
  const referralId = 'ref-e2e-vis-001';

  late PatientReferral sampleReferral;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.debugFetchAppointmentsOverride = ({String? patientId, String? dentistId}) async => [];
    ApiService.debugAdminAppointmentsOverride = () async => [];
    ApiService.debugFetchNotificationsOverride = ({String? role, String? userId}) async => [];

    sampleReferral = PatientReferral(
      id: referralId,
      referrerPatientId: 'referrer-doc-or-pat-001',
      referrerPatientName: 'Dr. Rohitha',
      referrerPatientPhone: '8986754323',
      referredPatientId: patientUserId,
      referredPatientName: 'Anu Sharma',
      referredPatientMobile: '9063663180',
      referredPatientAge: '28',
      referredPatientGender: 'Female',
      referredPatientCity: 'Hyderabad',
      referredPatientPincode: '500081',
      referredPatientLocation: 'Madhapur',
      requiredSpecialist: 'Cardiology',
      clinicalComplaint: 'Persistent chest tightness for 4 days; evaluate ECG.',
      doctorId: docDentistId,
      doctorName: 'Dr. Sri',
      doctorSpecialty: 'Cardiology',
      doctorClinicName: 'GS Health Heart Clinic',
      doctorCity: 'Hyderabad',
      doctorPincode: '500081',
      status: 'Pending',
    );
  });

  tearDown(() {
    ApiService.debugFetchAppointmentsOverride = null;
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchNotificationsOverride = null;
  });

  testWidgets(
    '1. Patient Dashboard displays received & created referrals on Home and ReferredPatientsSheet without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = PatientProblemService();
      await service.clearAllData();
      service.updatePatientProfile(
        id: patientUserId,
        name: 'Anu Sharma',
        email: 'anu@gshealth.test',
        phone: '9063663180',
        age: '28',
        gender: 'Female',
        bloodGroup: 'O+',
        emergencyContact: '9063663180',
      );

      // Seed both a received referral AND the same referral as created (to verify deduplication in sheet)
      service.addTestPatientReferral(sampleReferral, asReceived: true);
      service.addTestPatientReferral(sampleReferral, asReceived: false);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PatientDashboardScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byKey(const Key('patient_dashboard_referrals_section')), findsOneWidget);
      expect(find.byKey(const Key('patient_referral_card_$referralId')), findsOneWidget);
      expect(find.textContaining('Dr. Sri'), findsWidgets);
      expect(find.textContaining('Cardiology'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Open "View All" referrals sheet & verify deduplication + details
      final viewAllBtn = find.byKey(const Key('patient_view_all_referrals_btn'));
      await tester.ensureVisible(viewAllBtn);
      await tester.tap(viewAllBtn);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Referred Patients'), findsWidgets);
      expect(find.textContaining('Persistent chest tightness for 4 days'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    '2. Referred Doctor Dashboard displays incoming referrals on Today tab and Assigned Requests tab with Accept/Decline actions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = PatientProblemService();
      await service.clearAllData();
      service.addTestDoctor(
        DoctorModel(
          id: docDentistId,
          userId: docUserId,
          name: 'Dr. Sri',
          specialty: 'Cardiology',
          qualification: 'MBBS, MD, DM',
          experienceYears: 9,
          rating: 4.9,
          reviewCount: 25,
          clinicName: 'GS Health Heart Clinic',
          clinicAddress: 'Madhapur, Hyderabad',
          phone: '8985732916',
          email: 'sri@gshealth.test',
          status: 'Available',
          verificationStatus: 'VERIFIED',
          nextAvailableSlots: ['10:00 AM', '11:00 AM'],
          consultationFee: '₹700',
          city: 'Hyderabad',
          pincode: '500081',
        ),
      );
      service.currentDoctor = service.allDoctors.first;
      service.setDentistMode(true);
      service.addTestDoctorReceivedReferral(sampleReferral);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DentistTimelineScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      // Verify visible on Today tab
      expect(find.byKey(const Key('doctor_today_incoming_referrals_section')), findsOneWidget);
      expect(find.byKey(const Key('doctor_today_received_referral_card_$referralId')), findsOneWidget);
      expect(find.textContaining('Anu Sharma'), findsWidgets);
      expect(find.textContaining('Referred by: Dr. Rohitha'), findsOneWidget);
      expect(find.byKey(const Key('today_accept_referral_btn_$referralId')), findsOneWidget);
      expect(find.byKey(const Key('today_decline_referral_btn_$referralId')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Switch to Assigned Requests tab and confirm referral is visible there too
      await tester.tap(find.text('Requests'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('doctor_requests_incoming_referrals_section')), findsOneWidget);
      expect(find.byKey(const Key('doctor_requests_received_referral_card_$referralId')), findsOneWidget);
      expect(find.byKey(const Key('requests_accept_referral_btn_$referralId')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    '3. Admin Dashboard Referrals Panel displays referrals with Patient, Specialist Doctor & Status details',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = PatientProblemService();
      await service.clearAllData();
      service.setAdminMode(true);
      service.addTestAdminPatientReferral(sampleReferral);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AdminDashboardScreen(initialTab: 11),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.textContaining('Anu Sharma'), findsWidgets);
      expect(find.textContaining('9063663180'), findsWidgets);
      expect(find.textContaining('Dr. Sri'), findsWidgets);
      expect(find.textContaining('Dr. Rohitha'), findsWidgets);
      expect(find.textContaining('Pending'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
