import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/refer_a_friend_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final service = PatientProblemService();
    await service.clearAllData();
  });

  tearDown(() async {
    final service = PatientProblemService();
    await service.clearAllData();
  });

  testWidgets('Refer a Friend Screen renders all components matching GS HEALTH reference UI', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final testDoctor = DoctorModel(
      id: 'doc_test_1',
      name: 'Dr. Ananya Rao',
      specialty: 'Endodontist',
      qualification: 'BDS, MDS - Endodontics',
      clinicName: 'Bandra West Dental Clinic',
      city: 'Mumbai',
      pincode: '400050',
      clinicAddress: 'Linking Road, Bandra West',
      phone: '9876543210',
      email: 'ananya@example.com',
      status: 'Available',
      nextAvailableSlots: const ['10:00 AM', '02:00 PM'],
      consultationFee: '₹500',
      rating: 4.9,
      reviewCount: 48,
      experienceYears: 10,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ReferAFriendScreen(preselectedDoctor: testDoctor),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Header elements
    expect(find.text('Refer a friend'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

    // 2. Subtitle Description
    expect(
      find.text('Share a dentist you trust. We\'ll keep track of the referral for you.'),
      findsOneWidget,
    );

    // 3. Friend's Name Field
    expect(find.text('FRIEND\'S NAME'), findsOneWidget);
    expect(find.text('e.g. Amit Verma'), findsOneWidget);

    // 4. Friend's Mobile Field
    expect(find.text('FRIEND\'S MOBILE (+91)'), findsOneWidget);
    expect(find.text('98765 43210'), findsOneWidget);

    // 5. Refer To Section
    expect(find.text('REFER TO'), findsOneWidget);
    expect(find.text('Search dentist by name, specialty...'), findsOneWidget);
    expect(
      find.text('Showing your favourite and visited dentists. Search to find others.'),
      findsOneWidget,
    );

    // Doctor Card details
    expect(find.text('Dr. Ananya Rao'), findsOneWidget);
    expect(find.textContaining('Endodontist'), findsOneWidget);

    // 6. Note (Optional)
    expect(find.text('NOTE (OPTIONAL)'), findsOneWidget);
    expect(find.text('e.g. Looking for braces consultation'), findsOneWidget);

    // Scroll down to see attachments and submit button
    final scrollFinder = find.byType(Scrollable).first;
    await tester.drag(scrollFinder, const Offset(0, -400));
    await tester.pumpAndSettle();

    // 7. Attachments section
    expect(
      find.text('ATTACH PHOTOS, X-RAYS OR REPORTS (OPTIONAL) (0/5)'),
      findsOneWidget,
    );
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);

    // 8. Send referral button
    expect(find.text('Send referral'), findsOneWidget);
  });

  testWidgets('Refer a Friend Screen performs proper mobile and name validation', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final testDoctor = DoctorModel(
      id: 'doc_test_2',
      name: 'Dr. Sameer Joshi',
      specialty: 'Orthodontist',
      qualification: 'BDS, MDS',
      clinicName: 'Smile Care Center',
      city: 'Pune',
      pincode: '411001',
      clinicAddress: 'FC Road',
      phone: '9822001122',
      email: 'sameer@example.com',
      status: 'Available',
      nextAvailableSlots: const ['11:00 AM', '03:00 PM'],
      consultationFee: '₹600',
      rating: 4.8,
      reviewCount: 32,
      experienceYears: 8,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ReferAFriendScreen(preselectedDoctor: testDoctor),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll to reveal Send referral button
    final scrollFinder = find.byType(Scrollable).first;
    await tester.drag(scrollFinder, const Offset(0, -400));
    await tester.pumpAndSettle();

    // Tap Send referral with empty fields
    final sendButton = find.text('Send referral');
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    // Validation messages should appear
    expect(find.text('Please enter your friend\'s full name.'), findsOneWidget);
    expect(find.text('Please enter your friend\'s 10-digit mobile number.'), findsOneWidget);

    // Scroll back up and enter invalid mobile
    await tester.drag(scrollFinder, const Offset(0, 400));
    await tester.pumpAndSettle();

    final nameField = find.byKey(const ValueKey('referral_friend_name_input'));
    final mobileField = find.byKey(const ValueKey('referral_friend_mobile_input'));

    await tester.enterText(nameField, 'Rohit Sharma');
    await tester.enterText(mobileField, '12345'); // invalid
    await tester.pumpAndSettle();

    // Scroll down and tap send again
    await tester.drag(scrollFinder, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid 10-digit Indian mobile number.'), findsOneWidget);

    // Fix mobile to valid 10-digit number starting with 6-9
    await tester.drag(scrollFinder, const Offset(0, 400));
    await tester.pumpAndSettle();
    await tester.enterText(mobileField, '9876543210');
    await tester.pumpAndSettle();

    // Scroll down and tap send again
    await tester.drag(scrollFinder, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(sendButton);
    await tester.pump();

    // Validation errors should disappear
    expect(find.text('Please enter a valid 10-digit Indian mobile number.'), findsNothing);
  });

  testWidgets('Refer a Friend Screen is responsive across multiple viewport sizes without overflow', (tester) async {
    final viewports = [
      const Size(320, 640), // Very narrow phone
      const Size(360, 740), // Standard Android
      const Size(390, 844), // iPhone 14/15
      const Size(412, 915), // Pixel 7/8
    ];

    for (final size in viewports) {
      tester.view.physicalSize = size * 2.0;
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ReferAFriendScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No assertion or overflow error thrown
      expect(tester.takeException(), isNull);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
