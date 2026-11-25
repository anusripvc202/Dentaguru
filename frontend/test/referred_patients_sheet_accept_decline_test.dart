import 'package:dentaguru/core/models/referral_model.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/widgets/referred_patients_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PatientProblemService service;
  final List<String> acceptedIds = [];
  final List<(String id, String? reason)> rejectedCalls = [];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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
    service = PatientProblemService();
    await service.clearAllData();
  });

  tearDown(() async {
    ApiService.debugAcceptPatientReferralOverride = null;
    ApiService.debugRejectPatientReferralOverride = null;
    await service.clearAllData();
  });

  PatientReferral makePendingReferral(String id, String patientName) {
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
      status: 'Pending',
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

  testWidgets('1. ReferredPatientsSheet displays Accept & Decline buttons on pending referrals and handles Accept', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    service.addTestPatientReferral(makePendingReferral('ref-satya-1', 'satya'), asReceived: false);

    await openSheet(tester);

    expect(find.text('🟡 Doctor Reviewing'), findsOneWidget);
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
    expect(find.text('🟢 Accepted by Doctor'), findsOneWidget);
    expect(find.byKey(const Key('referred_sheet_accept_btn_ref-satya-1')), findsNothing);
    expect(find.byKey(const Key('referred_sheet_decline_btn_ref-satya-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2. ReferredPatientsSheet Decline opens confirmation dialog, saves reason & updates card to Declined', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    service.addTestPatientReferral(makePendingReferral('ref-satya-2', 'satya'), asReceived: false);

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
    expect(find.text('🔴 Referral Declined'), findsOneWidget);
    expect(find.text('Reason: Rescheduling for next week'), findsOneWidget);
    expect(find.byKey(const Key('referred_sheet_accept_btn_ref-satya-2')), findsNothing);
    expect(find.byKey(const Key('referred_sheet_decline_btn_ref-satya-2')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
