import 'package:dentaguru/core/models/referral_model.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/patient/presentation/widgets/referred_patients_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PatientProblemService service;
  final List<String> acceptedIds = [];
  final List<(String id, String? reason)> rejectedCalls = [];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    acceptedIds.clear();
    rejectedCalls.clear();
    ApiService.debugAcceptPatientReferralOverride = (String referralId, {String? confirmedTimeSlot}) async {
      acceptedIds.add(referralId);
      return {'success': true};
    };
    ApiService.debugRejectPatientReferralOverride = (String referralId, {String? rejectionReason}) async {
      rejectedCalls.add((referralId, rejectionReason));
      return {'success': true};
    };
    await SessionService().clearSession();
    service = PatientProblemService();
    await service.clearAllData();
  });

  tearDown(() async {
    ApiService.debugAcceptPatientReferralOverride = null;
    ApiService.debugRejectPatientReferralOverride = null;
    await SessionService().clearSession();
    await service.clearAllData();
  });

  PatientReferral makeReferral(
    String id,
    String patientName, {
    String status = 'Pending',
    String? rejectionReason,
  }) {
    return PatientReferral(
      id: id,
      referrerPatientId: 'pat-1',
      referrerPatientName: 'Anu',
      referredPatientId: 'pat-2',
      referredPatientName: patientName,
      referredPatientMobile: '9063663179',
      referredPatientCity: 'hyd',
      referredPatientPincode: '500100',
      referredPatientLocation: 'kompally',
      requiredSpecialist: 'Dermatology',
      clinicalComplaint: 'Referral consultation with Dr. rohitha',
      doctorId: 'doc-1',
      doctorName: 'Dr. rohitha',
      doctorSpecialty: 'Dermatology',
      doctorClinicName: 'devi clinic',
      doctorCity: 'hyd',
      doctorPincode: '500100',
      doctorLocation: 'kompally',
      status: status,
      rejectionReason: rejectionReason,
    );
  }

  Future<void> loginAsPatient() async {
    await SessionService().saveSession(
      userId: 'pat-1',
      role: 'Patient',
      name: 'Anu',
      email: 'anu@gshealth.test',
      phone: '9876543210',
      token: 'pat-jwt',
    );
    service.currentPatient = PatientProfile(
      id: 'pat-1',
      name: 'Anu',
      phone: '9876543210',
      city: 'Hyderabad',
    );
  }

  Future<void> loginAsAssignedDoctor() async {
    await SessionService().saveSession(
      userId: 'doc-user-1',
      role: 'Dentist',
      name: 'Dr. rohitha',
      email: 'rohitha@gshealth.test',
      phone: '9988776655',
      token: 'doc-jwt',
    );
    service.registerDoctor(
      id: 'doc-1',
      userId: 'doc-user-1',
      name: 'Dr. rohitha',
      specialty: 'Dermatology',
      qualification: 'MBBS, MD',
      experienceYears: 7,
      clinicName: 'devi clinic',
      phone: '9988776655',
      email: 'rohitha@gshealth.test',
      licenseNumber: 'MED-DERM-01',
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                key: const Key('open_referred_sheet_btn'),
                onPressed: () => ReferredPatientsSheet.show(ctx),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_referred_sheet_btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets(
    '1. Patient session sees read-only statuses (Pending, Accepted, Rejected, Completed) with NO Accept/Decline actions and cannot self-accept/reject',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await loginAsPatient();
      service.addTestPatientReferral(makeReferral('ref-p-1', 'Satya', status: 'Pending'), asReceived: false);
      service.addTestPatientReferral(makeReferral('ref-p-2', 'Meera', status: 'Accepted'), asReceived: false);
      service.addTestPatientReferral(
        makeReferral('ref-p-3', 'Kiran', status: 'Rejected', rejectionReason: 'Doctor on leave'),
        asReceived: false,
      );
      service.addTestPatientReferral(makeReferral('ref-p-4', 'Ravi', status: 'Completed'), asReceived: false);

      await openSheet(tester);

      // Patient MUST NOT see Accept, Decline, Mark Contacted, or Mark Completed buttons
      expect(find.byKey(const Key('referred_sheet_accept_btn_ref-p-1')), findsNothing);
      expect(find.byKey(const Key('referred_sheet_decline_btn_ref-p-1')), findsNothing);
      expect(find.byKey(const Key('referred_sheet_contacted_btn_ref-p-2')), findsNothing);
      expect(find.byKey(const Key('referred_sheet_completed_btn_ref-p-2')), findsNothing);

      // Read-only status badges & descriptions are clearly visible
      expect(find.text('Pending – Waiting for doctor response'), findsOneWidget);
      expect(find.text('Accepted – Doctor accepted the referral'), findsOneWidget);

      // Scroll to verify Rejected and Completed cards are also read-only
      await tester.scrollUntilVisible(
        find.byKey(const Key('referred_sheet_card_ref-p-4')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Rejected – Doctor rejected the referral'), findsOneWidget);
      expect(find.text('Reason: Doctor on leave'), findsOneWidget);
      expect(find.text('Completed – Referral process completed'), findsOneWidget);

      // Programmatic guard: Patient cannot accept or reject their own referral
      final acceptAttempt = await service.acceptPatientReferralByDoctor('ref-p-1');
      final rejectAttempt = await service.rejectPatientReferralByDoctor('ref-p-1', rejectionReason: 'Self');
      expect(acceptAttempt, isFalse);
      expect(rejectAttempt, isFalse);
      expect(acceptedIds, isEmpty);
      expect(rejectedCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '2. Assigned Doctor session displays Accept & Decline buttons on pending referrals and handles Accept',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await loginAsAssignedDoctor();
      service.addTestPatientReferral(makeReferral('ref-satya-1', 'satya'), asReceived: false);

      await openSheet(tester);

      expect(find.text('Pending – Waiting for doctor response'), findsOneWidget);
      final acceptBtn = find.byKey(const Key('referred_sheet_accept_btn_ref-satya-1'));
      final declineBtn = find.byKey(const Key('referred_sheet_decline_btn_ref-satya-1'));
      expect(acceptBtn, findsOneWidget);
      expect(declineBtn, findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(acceptBtn);
      await tester.tap(acceptBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(acceptedIds, equals(['ref-satya-1']));
      expect(find.text('Accepted – Doctor accepted the referral'), findsOneWidget);
      expect(find.byKey(const Key('referred_sheet_accept_btn_ref-satya-1')), findsNothing);
      expect(find.byKey(const Key('referred_sheet_decline_btn_ref-satya-1')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '3. Assigned Doctor session Decline opens confirmation dialog, saves reason & updates card to Rejected',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await loginAsAssignedDoctor();
      service.addTestPatientReferral(makeReferral('ref-satya-2', 'satya'), asReceived: false);

      await openSheet(tester);

      final declineBtn = find.byKey(const Key('referred_sheet_decline_btn_ref-satya-2'));
      await tester.ensureVisible(declineBtn);
      await tester.tap(declineBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Decline Referral'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Rescheduling for next week');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Decline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(rejectedCalls, equals([('ref-satya-2', 'Rescheduling for next week')]));
      expect(find.text('Rejected – Doctor rejected the referral'), findsOneWidget);
      expect(find.text('Reason: Rescheduling for next week'), findsOneWidget);
      expect(find.byKey(const Key('referred_sheet_accept_btn_ref-satya-2')), findsNothing);
      expect(find.byKey(const Key('referred_sheet_decline_btn_ref-satya-2')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
