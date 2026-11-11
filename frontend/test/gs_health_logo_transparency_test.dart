import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/core/constants/gs_health_brand_assets.dart';
import 'package:dentaguru/core/widgets/denta_guru_logo.dart';
import 'package:dentaguru/core/widgets/session_gate_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<ui.Image> decodeBase64Png(String b64) async {
    final Uint8List bytes = base64Decode(b64);
    expect(bytes.length, greaterThan(8));
    // Verify strict PNG magic bytes (%PNG)
    expect(bytes.sublist(0, 4), equals(<int>[0x89, 0x50, 0x4E, 0x47]));
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  test('Embedded GS HEALTH logo assets are valid transparent RGBA PNGs with original dimensions', () async {
    final lightLogo = await decodeBase64Png(kGsHealthLogoBase64);
    final darkLogo = await decodeBase64Png(kGsHealthLogoDarkBgBase64);
    final lightIcon = await decodeBase64Png(kGsHealthAppIconBase64);
    final darkIcon = await decodeBase64Png(kGsHealthAppIconDarkBgBase64);

    expect(lightLogo.width, 1024);
    expect(lightLogo.height, 682);
    expect(darkLogo.width, 1024);
    expect(darkLogo.height, 682);
    expect(lightIcon.width, 512);
    expect(lightIcon.height, 512);
    expect(darkIcon.width, 512);
    expect(darkIcon.height, 512);

    // Confirm corner pixels have alpha == 0 (completely transparent, not white rectangle)
    for (final img in [lightLogo, darkLogo, lightIcon, darkIcon]) {
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(bd, isNotNull);
      // Top-left pixel (0,0) alpha byte is index 3
      expect(bd!.getUint8(3), equals(0), reason: 'Top-left corner pixel must be transparent');
      // Bottom-right pixel alpha byte
      final lastPixelAlphaOffset = (img.width * img.height - 1) * 4 + 3;
      expect(bd.getUint8(lastPixelAlphaOffset), equals(0), reason: 'Bottom-right corner pixel must be transparent');
    }
  });

  testWidgets('DentaGuruLogo renders without any white box, border, shadow, or container on light & dark backgrounds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF0F172A),
          body: Column(
            children: [
              DentaGuruLogo(height: 36, darkBg: false),
              DentaGuruLogo(height: 46, darkBg: true),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DentaGuruLogo), findsNWidgets(2));
    // Verify NO Container or DecoratedBox wrapper is inside DentaGuruLogo
    expect(
      find.descendant(of: find.byType(DentaGuruLogo), matching: find.byType(Container)),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(DentaGuruLogo), matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(DentaGuruLogo), matching: find.byType(Image)),
      findsNWidgets(2),
    );
  });

  testWidgets('SessionGateScreen renders DentaGuruToothIcon directly without white circle background container', (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SessionGateScreen()),
        GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('Login'))),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final iconFinder = find.byType(DentaGuruToothIcon);
    expect(iconFinder, findsOneWidget);

    final iconWidget = tester.widget<DentaGuruToothIcon>(iconFinder);
    expect(iconWidget.darkBg, isTrue);

    // Ensure no ClipOval or white circular Container wraps DentaGuruToothIcon
    expect(find.ancestor(of: iconFinder, matching: find.byType(ClipOval)), findsNothing);

    // Drain pending navigation timers cleanly
    await tester.pump(const Duration(seconds: 2));
  });
}

