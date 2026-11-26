import 'package:dentaguru/core/models/referral_model.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/refer_a_friend_screen.dart';
import 'package:dentaguru/features/patient/presentation/widgets/referred_patients_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PatientProblemService service;
  final List<Map<String, dynamic>> createdReferrals = [];
  final List<(String id, String status)> statusUpdates = [];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionService().clearSession();
    createdReferrals.clear();
    statusUpdates.clear();
    service = PatientProblemService();
    await service.clearAllData();

    ApiService.debugCreatePatientReferralOverride = ({
      required String referredPatientName,
      required String referredPatientMobile,
      required String doctorId,
      String? referrerPatientId,
    }) async {
      createdReferrals.add({
        'name': referredPatientName,
        'mobile': referredPatientMobile,
        'doctorId': doctorId,
      });
      return {
        'success': true,
        'referral': {
          'id': 'ref-phase6-${createdReferrals.length}',
          'referrer_patient_id': referrerPatientId ?? 'pat-1',
          'referred_patient_name': referredPatientName,
          'referred_patient_mobile': referredPatientMobile,
          'required_specialist': 'Cardiology',
          'doctor_id': doctorId,
          'status': 'Pending',
        },
      };
    };

    ApiService.debugUpdatePatientReferralStatusOverride = (
      String referralId, {
      required String status,
      String? reason,
    }) async {
      statusUpdates.add((referralId, status));
      return {'success': true};
    };
  });

  tearDown(() async {
    ApiService.debugCreatePatientReferralOverride = null;
    ApiService.debugUpdatePatientReferralStatusOverride = null;
    await service.clearAllData();
  });

  testWidgets(
    '1. Patient with 0 favourite doctors can submit specialty-only referral via confirmation dialog',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      expect(service.myDoctors, isEmpty);
      service.addTestDoctor(
        DoctorModel(
          id: 'doc-cardio-1',
          name: 'Dr. Kavita Menon',
          specialty: 'Cardiology',
          qualification: 'MD, DM Cardiology',
          clinicName: 'Heart Care',
          phone: '9876500001',
          email: 'kavita@example.com',
          status: 'Available',
          nextAvailableSlots: const ['10:00 AM'],
          consultationFee: '₹900',
          rating: 0,
          reviewCount: 0,
          experienceYears: 9,
        ),
      );
      service.addTestDoctor(
        DoctorModel(
          id: 'doc-dental-1',
          name: 'Dr. Rohan Gupta',
          specialty: 'Dentistry',
          qualification: 'BDS',
          clinicName: 'Dental Studio',
          phone: '9876500002',
          email: 'rohan@example.com',
          status: 'Available',
          nextAvailableSlots: const ['11:00 AM'],
          consultationFee: '₹500',
          rating: 0,
          reviewCount: 0,
          experienceYears: 6,
        ),
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: ReferAFriendScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('referral_friend_name_input')),
        'Vikram Nair',
      );
      await tester.enterText(
        find.byKey(const ValueKey('referral_friend_mobile_input')),
        '9876543211',
      );

      await tester.tap(find.byKey(const Key('referral_specialty_chip_Cardiology')));
      await tester.pumpAndSettle();

      expect(find.text('Dr. Kavita Menon'), findsOneWidget);
      expect(find.text('Dr. Rohan Gupta'), findsNothing);

      // Keep "No specific doctor" selected
      await tester.tap(find.byKey(const Key('referral_no_specific_doctor_option')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('referral_send_button')));
      await tester.tap(find.byKey(const ValueKey('referral_send_button')));
      await tester.pumpAndSettle();

      // In-app confirmation dialog appears, WhatsApp opt-in defaults to false
      expect(find.byKey(const Key('referral_confirmation_dialog')), findsOneWidget);
      final cb = tester.widget<CheckboxListTile>(
        find.byKey(const Key('referral_confirm_whatsapp_checkbox')),
      );
      expect(cb.value, isFalse);
      expect(createdReferrals, isEmpty);

      await tester.tap(find.byKey(const Key('referral_confirm_submit_button')));
      await tester.pumpAndSettle();

      expect(createdReferrals, hasLength(1));
      expect(createdReferrals.first['name'], 'Vikram Nair');
      expect(createdReferrals.first['doctorId'], isEmpty);
    },
  );

  testWidgets(
    '2. ReferredPatientsSheet supports 5 referral statuses and Contacted -> Completed transitions',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await SessionService().saveSession(
        userId: 'doc-neuro-user-1',
        role: 'Dentist',
        name: 'Dr. Neuro Specialist',
        email: 'neuro@gshealth.test',
        phone: '9988776611',
        token: 'doc-neuro-jwt',
      );
      service.registerDoctor(
        id: 'doc-neuro-1',
        userId: 'doc-neuro-user-1',
        name: 'Dr. Neuro Specialist',
        specialty: 'Neurology',
        qualification: 'MBBS, DM',
        experienceYears: 8,
        clinicName: 'Neuro Care',
        phone: '9988776611',
        email: 'neuro@gshealth.test',
        licenseNumber: 'MED-NEURO-1',
      );

      service.addTestPatientReferral(
        PatientReferral(
          id: 'ref-status-1',
          referrerPatientId: 'pat-1',
          referredPatientName: 'Meera Kapoor',
          referredPatientMobile: '9876543219',
          requiredSpecialist: 'Neurology',
          clinicalComplaint: 'Migraine follow-up',
          doctorId: 'doc-neuro-1',
          doctorName: 'Dr. Neuro Specialist',
          status: 'Accepted',
        ),
        asReceived: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  key: const Key('open_sheet_btn'),
                  onPressed: () => ReferredPatientsSheet.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open_sheet_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Contacted'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      await tester.tap(find.byKey(const Key('referred_sheet_contacted_btn_ref-status-1')));
      await tester.pumpAndSettle();

      expect(statusUpdates.any((u) => u.$1 == 'ref-status-1' && u.$2 == 'Contacted'), isTrue);
      expect(find.text('Contacted – Doctor contacted the patient'), findsOneWidget);

      await tester.tap(find.byKey(const Key('referred_sheet_completed_btn_ref-status-1')));
      await tester.pumpAndSettle();

      expect(statusUpdates.any((u) => u.$1 == 'ref-status-1' && u.$2 == 'Completed'), isTrue);
      expect(find.text('Completed – Referral process completed'), findsOneWidget);
    },
  );
}
