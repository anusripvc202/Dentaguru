import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/main.dart';
import 'package:dentaguru/features/auth/presentation/screens/auth_screen.dart';
import 'package:dentaguru/core/services/api_service.dart';

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

  testWidgets('Patient Registration mandatory fields, optional fields, and 6-digit Pincode validation', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AuthScreen(initialRole: 'patient', initialTab: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final formFinder = find.byType(Form);
    final FormState formState = tester.state<FormState>(formFinder.first);

    // 1. Empty form fails validation on the 4 mandatory fields only
    expect(formState.validate(), isFalse);
    await tester.pump();
    expect(find.text('Please enter your name'), findsOneWidget);
    expect(find.text('Mobile phone number is mandatory'), findsOneWidget);
    expect(find.text('Please enter your city'), findsOneWidget);
    expect(find.text('Enter Pincode'), findsOneWidget);

    // 2. Fill the 4 mandatory fields while leaving Language, Location/Address, Email, Age, etc. empty
    final textFields = find.byType(TextFormField);
    await tester.enterText(textFields.at(0), 'Aarav Sharma'); // Patient Full Name *
    await tester.enterText(textFields.at(2), '9876543219');   // Mobile Phone Number *
    await tester.enterText(textFields.at(3), 'Hyderabad');    // City *
    await tester.enterText(textFields.at(4), '50008');        // Invalid 5-digit Pincode *
    expect(formState.validate(), isFalse);
    await tester.pump();
    expect(find.text('6-digit PIN'), findsOneWidget);

    // 3. Enter valid 6-digit Pincode -> form validation passes with optional fields empty
    await tester.enterText(textFields.at(4), '500081');
    expect(formState.validate(), isTrue);
  });

  testWidgets('Dentist Registration enforces License Number, Specialty, and Clinic Name validators', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AuthScreen(initialRole: 'dentist', initialTab: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final formFinder = find.byType(Form);
    final FormState formState = tester.state<FormState>(formFinder.first);
    expect(formState.validate(), isFalse);
    await tester.pump();

    expect(find.text('Enter Dental License Number'), findsOneWidget);
    expect(find.text('Enter clinic name'), findsOneWidget);
  });

  test('ApiService.registerUser rejects empty or invalid phone numbers without false duplicate error', () async {
    final emptyRes = await ApiService().registerUser(
      name: 'Test Patient',
      phone: '',
      city: 'Hyderabad',
      pincode: '500081',
    );
    expect(emptyRes['success'], isFalse);
    expect(emptyRes['message'], contains('valid 10-digit mobile phone number'));
    expect(emptyRes['message'], isNot(contains('already registered')));
  });
}
