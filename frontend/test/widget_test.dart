import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/main.dart';
import 'package:dentaguru/features/auth/presentation/screens/auth_screen.dart';
import 'package:dentaguru/features/clinic/presentation/screens/clinic_dashboard.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/models/medical_specialty_model.dart';

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

  testWidgets('Patient Registration enforces ONLY Full Name and Contact Number as mandatory', (WidgetTester tester) async {
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

    // 1. Empty form fails validation ONLY on Full Name and Contact Number
    expect(formState.validate(), isFalse);
    await tester.pump();
    expect(find.text('Please enter your name'), findsOneWidget);
    expect(find.text('Mobile phone number is mandatory'), findsOneWidget);
    // City and Pincode are optional: no validation error when empty
    expect(find.text('Please enter your city'), findsNothing);
    expect(find.text('Enter Pincode'), findsNothing);

    // 2. If user enters an invalid 5-digit Pincode, format check applies
    final textFields = find.byType(TextFormField);
    await tester.enterText(textFields.at(0), 'Aarav Sharma'); // Patient Full Name *
    await tester.enterText(textFields.at(2), '9876543219');   // Mobile Phone Number *
    await tester.enterText(textFields.at(4), '50008');        // Invalid 5-digit Pincode (optional format check)
    expect(formState.validate(), isFalse);
    await tester.pump();
    expect(find.text('6-digit PIN'), findsOneWidget);

    // 3. Clear pincode (leave blank) -> validation passes since it is optional
    await tester.enterText(textFields.at(4), '');
    expect(formState.validate(), isTrue);

    // 4. Enter valid 6-digit Pincode -> validation also passes
    await tester.enterText(textFields.at(4), '500081');
    expect(formState.validate(), isTrue);
  });

  testWidgets('Dentist Registration enforces ONLY Full Name and Contact Number, keeping License and Clinic optional', (WidgetTester tester) async {
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

    // Mandatory fields
    expect(find.text('Please enter your name'), findsOneWidget);
    expect(find.text('Mobile phone number is mandatory'), findsOneWidget);

    // Optional fields should NOT produce validation errors
    expect(find.text('Enter Dental License Number'), findsNothing);
    expect(find.text('Enter clinic name'), findsNothing);

    // Providing only Full Name and Contact Number passes validation
    final textFields = find.byType(TextFormField);
    await tester.enterText(textFields.at(0), 'Dr. Priya Nair');
    await tester.enterText(textFields.at(2), '9812345678');
    expect(formState.validate(), isTrue);
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

  testWidgets('ClinicDashboardScreen Add Doctor button opens Add Attached Doctor dialog', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ClinicDashboardScreen(),
        ),
      ),
    );
    await tester.pump();

    // Switch to Doctors tab
    await tester.tap(find.text('Doctors'));
    await tester.pumpAndSettle();

    // Tap Add Doctor button
    expect(find.text('Add Doctor'), findsOneWidget);
    await tester.tap(find.text('Add Doctor'));
    await tester.pumpAndSettle();

    expect(find.text('Add Attached Doctor'), findsOneWidget);
  });

  test('Multi-Specialty Platform supports all 16 core medical specialties and backward-compatible dental matching', () {
    final defaultNames = MedicalSpecialtyModel.defaultSpecialties.map((s) => s.name).toList();
    const expectedSpecialties = [
      'General Medicine',
      'Cardiology',
      'Dermatology',
      'Neurology',
      'Orthopedics',
      'Pediatrics',
      'Gynecology',
      'ENT',
      'Ophthalmology',
      'Oncology',
      'Urology',
      'Psychiatry',
      'Gastroenterology',
      'Pulmonology',
      'Endocrinology',
      'Dentistry',
    ];
    for (final spec in expectedSpecialties) {
      expect(defaultNames, contains(spec));
    }

    // Backward-compatible dental matching
    expect(MedicalSpecialtyModel.matchesSpecialtyFilter('General Dentistry', 'Dentistry'), isTrue);
    expect(MedicalSpecialtyModel.matchesSpecialtyFilter('Orthodontics', 'Dentistry'), isTrue);
    expect(MedicalSpecialtyModel.matchesSpecialtyFilter('Cardiology', 'Dentistry'), isFalse);
    expect(MedicalSpecialtyModel.matchesSpecialtyFilter('Cardiology', 'Cardiology'), isTrue);

    // Default qualifications
    expect(MedicalSpecialtyModel.getDefaultQualificationForSpecialty('Cardiology'), equals('MBBS, MD, DM (Cardiology)'));
    expect(MedicalSpecialtyModel.getDefaultQualificationForSpecialty('General Dentistry'), equals('BDS, MDS'));
  });

  testWidgets('FindDoctorsScreen displays multi-specialty filter chips and City/Pincode filters', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: FindDoctorsScreen(initialSpecialty: 'Cardiology'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Find Doctors'), findsOneWidget);
    expect(find.byKey(const ValueKey('find_doctors_search_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter_city_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter_pincode_input')), findsOneWidget);
    expect(find.text('Cardiology'), findsWidgets);
    expect(find.text('Dentistry'), findsWidgets);
  });

  test('PatientProblemService supports dynamic Admin specialty creation, toggle, and analytics breakdown', () async {
    final service = PatientProblemService();
    final initialCount = service.specialties.length;
    expect(initialCount, greaterThanOrEqualTo(16));

    final added = await service.addMedicalSpecialty(
      name: 'Nephrology',
      department: 'Renal Sciences',
      description: 'Kidney care and dialysis management',
      defaultQualifications: 'MBBS, MD, DM',
    );
    expect(added.name, equals('Nephrology'));
    expect(service.specialties.any((s) => s.name == 'Nephrology'), isTrue);

    await service.toggleMedicalSpecialtyStatus(added.id, false);
    final updated = service.specialties.firstWhere((s) => s.id == added.id);
    expect(updated.isActive, isFalse);

    final breakdown = service.getSpecialtyAnalyticsBreakdown();
    expect(breakdown.any((row) => row['name'] == 'Cardiology'), isTrue);
    expect(breakdown.any((row) => row['name'] == 'Dentistry'), isTrue);
  });

  testWidgets('AdminDashboardScreen Specialties tab renders all specialty cards without TypeError', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AdminDashboardScreen(),
        ),
      ),
    );
    await tester.pump();

    // Tap the mobile "Specialties" nav pill
    await tester.ensureVisible(find.text('Specialties'));
    await tester.tap(find.text('Specialties'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('+ Add Specialty'), findsOneWidget);
    expect(find.text('General Medicine'), findsOneWidget);
    expect(find.text('Cardiology'), findsOneWidget);
  });
}
