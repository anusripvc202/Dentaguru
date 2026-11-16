import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/core/theme/app_theme.dart';
import 'package:dentaguru/core/widgets/denta_guru_logo.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';

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

  testWidgets('GS HEALTH Patient Dashboard redesign matches exact reference layout and 2-color brand system', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PatientDashboardScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // 1. Header Verification
    expect(find.byType(GsHealthLogo), findsWidgets);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is Text &&
          (widget.data == 'Good morning' ||
              widget.data == 'Good afternoon' ||
              widget.data == 'Good evening')),
      findsOneWidget,
    );
    expect(find.text('Anu'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

    // 2. Section 1: Upcoming Visits Hero Banner
    expect(find.text('YOUR SMILE, CARED FOR'), findsOneWidget);
    expect(find.text('No upcoming visits'), findsOneWidget);
    expect(
      find.text('Book a verified dentist near you in under a minute.'),
      findsOneWidget,
    );

    // 3. Section 2: AI Dental Triage Card ("Something hurting?")
    expect(find.text('Something hurting?'), findsOneWidget);
    expect(
      find.text('Describe it and our AI tells you how urgent it is and who to see.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);

    // 4. Section 3: Talk to a Dentist Card
    expect(find.text('Talk to a dentist now'), findsOneWidget);
    expect(
      find.text('Get matched with an online dentist who speaks your language.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);

    // 5. Section 4: Sponsored Banner ("GS IMPLANTS")
    expect(find.text('SPONSORED'), findsOneWidget);
    expect(find.text('GS IMPLANTS'), findsOneWidget);
    expect(find.text('Most economic dental implants'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);

    // Scroll down to reveal lower sections
    final scrollFinder = find.byType(Scrollable).first;
    await tester.drag(scrollFinder, const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 500));

    // 6. Section 5: My Favourite Dentists Section
    expect(find.text('My favourite dentists'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(find.text('No favourites yet'), findsOneWidget);
    expect(
      find.text('Tap ❤️ on a dentist\'s profile to save them here and refer friends to them.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    // 7. Section 6: Refer a Friend Section
    expect(find.text('Refer a friend'), findsOneWidget);
    expect(
      find.text('Share a dentist you trust and track the referral.'),
      findsOneWidget,
    );
    expect(find.text('My referrals'), findsOneWidget);
    expect(find.byIcon(Icons.card_giftcard_rounded), findsOneWidget);

    // 8. Fixed Bottom Navigation Bar Verification
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Find'), findsOneWidget);
    expect(find.text('Visits'), findsOneWidget);
    expect(find.text('Locker'), findsOneWidget);

    // 9. Verify 2-Color Brand System in Theme
    expect(AppTheme.gsNavy, const Color(0xFF012A58));
    expect(AppTheme.gsRed, const Color(0xFFFE3434));
    expect(AppTheme.primaryBlue, AppTheme.gsNavy);
    expect(AppTheme.brandOrange, AppTheme.gsRed);
  });

  testWidgets('Patient Dashboard is responsive without RenderFlex overflows across narrow & standard viewports', (tester) async {
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
            home: PatientDashboardScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Scroll through dashboard to ensure all elements layout without overflow
      final scrollFinder = find.byType(Scrollable).first;
      await tester.drag(scrollFinder, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
