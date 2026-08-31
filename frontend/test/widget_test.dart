import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('DentaGuruApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DentaGuruApp()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(DentaGuruApp), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
  });
}
