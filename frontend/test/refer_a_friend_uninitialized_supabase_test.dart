import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/services/supabase_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/refer_a_friend_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SupabaseService.resetForTesting();
    ApiService.debugCreatePatientReferralOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    ApiService.debugCreatePatientReferralOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  group('Refer a Friend & Referral APIs without initialized Supabase', () {
    test('1. Safe Supabase guard prevents AssertionError across referral APIs when Supabase is uninitialized', () async {
      expect(SupabaseService.isInitialized, isFalse);
      expect(SupabaseService.safeClient, isNull);

      // Should never throw AssertionError: You must initialize the supabase instance
      final createRes = await ApiService().createPatientReferral(
        referredPatientName: 'Amit Verma',
        referredPatientMobile: '9876543210',
        referredPatientAge: 'Not specified',
        referredPatientGender: 'Not specified',
        referredPatientCity: 'Hyderabad',
        referredPatientPincode: '500081',
        referredPatientLocation: 'Devi Clinic',
        requiredSpecialist: 'Dermatology',
        clinicalComplaint: 'rashes',
        doctorId: 'doc-rohitha',
        referrerPatientId: 'pat-anu-1',
      );
      expect(createRes['success'], isFalse);
      final msg = (createRes['message'] ?? '').toString();
      expect(msg.contains('Supabase.instance'), isFalse);
      expect(msg.contains('_isInitialized'), isFalse);

      // Fetch methods must cleanly handle uninitialized Supabase without crashing
      expect(await ApiService().fetchMyPatientReferrals(userId: 'pat-anu-1'), isA<List<dynamic>>());
      expect(await ApiService().fetchDoctorPatientReferrals(doctorId: 'doc-rohitha'), isA<List<dynamic>>());
      expect(await ApiService().fetchReceivedPatientReferrals(patientId: 'pat-anu-1'), isA<List<dynamic>>());
    });

    testWidgets(
      '2. ReferAFriendScreen submits referral successfully through Express backend even when Supabase.instance is uninitialized and doctor has no clinicAddress',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: 'pat-anu-58df98d2',
          name: 'Anu',
          phone: '9063663180',
          city: 'Hyderabad',
          pincode: '500081',
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-rohitha',
            userId: 'u-rohitha',
            name: 'Dr. rohitha',
            specialty: 'Dermatology',
            qualification: 'MBBS, MD (Dermatology)',
            experienceYears: 6,
            rating: 4.9,
            reviewCount: 15,
            clinicName: '', // intentionally empty to test fallback resolution
            clinicAddress: '',
            phone: '8986754323',
            email: 'rohitha@gshealth.test',
            status: 'Available',
            city: '',
            pincode: '',
            nextAvailableSlots: const ['10:00 AM'],
            consultationFee: '₹600',
          ),
        );

        String? capturedDoctorId;
        String? capturedReferrerId;
        ApiService.debugCreatePatientReferralOverride = ({
          required String referredPatientName,
          required String referredPatientMobile,
          required String doctorId,
          String? referrerPatientId,
        }) async {
          capturedDoctorId = doctorId;
          capturedReferrerId = referrerPatientId;
          return {
            'success': true,
            'message': 'Referral submitted successfully.',
            'referral': {
              'id': 'ref-ok-1',
              'referrerPatientId': referrerPatientId,
              'referredPatientName': referredPatientName,
              'referredPatientMobile': referredPatientMobile,
              'doctorId': doctorId,
              'doctorName': 'Dr. rohitha',
              'requiredSpecialist': 'Dermatology',
              'clinicalComplaint': 'rashes',
              'status': 'Pending',
              'referralDate': DateTime.now().toIso8601String(),
            },
          };
        };

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(useMaterial3: false),
              home: const ReferAFriendScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.enterText(find.byKey(const ValueKey('referral_friend_name_input')), 'Ravi Kumar');
        await tester.enterText(find.byKey(const ValueKey('referral_friend_mobile_input')), '9876543210');
        await tester.enterText(find.byKey(const ValueKey('referral_note_input')), 'rashes');

        final docFinder = find.text('Dr. rohitha');
        await tester.ensureVisible(docFinder);
        await tester.pump();
        await tester.tap(docFinder);
        await tester.pump();

        final sendBtn = find.text('Send referral');
        await tester.ensureVisible(sendBtn);
        await tester.pump();
        await tester.tap(sendBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(const Key('referral_confirmation_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('referral_confirm_submit_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(capturedDoctorId, equals('doc-rohitha'));
        expect(capturedReferrerId, equals('pat-anu-58df98d2'));
        expect(find.text('Referral Sent!'), findsOneWidget);
        expect(find.textContaining('Supabase.instance'), findsNothing);
      },
    );
  });
}
