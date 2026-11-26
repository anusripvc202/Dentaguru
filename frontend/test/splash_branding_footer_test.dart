import 'package:dentaguru/core/widgets/session_gate_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SessionGateScreen()),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Center(child: Text('LOGIN_SCREEN_PLACEHOLDER'))),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  const sizes = <Size>[
    Size(320, 568), // iPhone SE (1st gen) / small Android
    Size(360, 640), // common Android
    Size(390, 844), // iPhone 14
    Size(412, 915), // Pixel 7 / large Android
    Size(768, 1024), // tablet
  ];

  for (final size in sizes) {
    testWidgets(
      'Splash shows "Designed by The Patterns Company" at bottom center without overlap at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.view.padding = const FakeViewPadding(bottom: 24, top: 24);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetPadding();
        });

        await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: _buildRouter())));
        await tester.pump();

        final branding = find.byKey(const Key('splash_designed_by_text'));
        expect(branding, findsOneWidget);
        expect(find.text('Designed by The Patterns Company', findRichText: true), findsOneWidget);
        expect(tester.takeException(), isNull);

        final brandingRect = tester.getRect(branding);
        final screen = Offset.zero & size;

        // Fully visible on screen, horizontally centred, near bottom and above bottom safe area.
        expect(screen.contains(brandingRect.topLeft) && screen.contains(brandingRect.bottomRight - const Offset(0.01, 0.01)), isTrue);
        expect((brandingRect.center.dx - size.width / 2).abs(), lessThan(1.0));
        expect(brandingRect.bottom, lessThanOrEqualTo(size.height - 24 - 16));
        expect(brandingRect.top, greaterThan(size.height * 0.75));
        // Headless test font renders every glyph as a full square (much wider than real fonts),
        // so FittedBox may scale it slightly on 320px; real devices render at full 11.5px.
        expect(brandingRect.height, greaterThanOrEqualTo(8));

        // No overlap with logo, title, tagline, loader or status text.
        for (final f in <Finder>[
          find.text('GS HEALTH'),
          find.text('Multi-Specialty Healthcare Platform'),
          find.byType(CircularProgressIndicator),
          find.textContaining('session'),
        ]) {
          if (f.evaluate().isEmpty) continue;
          final r = tester.getRect(f.first);
          expect(r.overlaps(brandingRect), isFalse, reason: 'Branding overlaps $f');
          expect(r.bottom, lessThan(brandingRect.top));
        }

        // Let splash navigation complete: credit must NOT appear on the login screen.
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('LOGIN_SCREEN_PLACEHOLDER'), findsOneWidget);
        expect(find.byKey(const Key('splash_designed_by_text')), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('Branding stays on one line without overflow at large accessibility text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: _buildRouter())));
    await tester.pump();

    expect(find.byKey(const Key('splash_designed_by_text')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byKey(const Key('splash_designed_by_text')));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
