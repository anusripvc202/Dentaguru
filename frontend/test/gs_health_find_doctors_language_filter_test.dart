import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:dentaguru/core/theme/app_theme.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';

Future<void> _loadRealSystemFontsForScreenshots() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final windir = Platform.environment['WINDIR'] ?? r'C:\Windows';
  final segoeRegular = File('$windir\\Fonts\\segoeui.ttf');
  final segoeBold = File('$windir\\Fonts\\segoeuib.ttf');
  final segoeSemiBold = File('$windir\\Fonts\\seguisb.ttf');
  final segoeSymbol = File('$windir\\Fonts\\seguisym.ttf');

  if (segoeRegular.existsSync()) {
    final regularBytes = await segoeRegular.readAsBytes();
    final boldBytes = segoeBold.existsSync() ? await segoeBold.readAsBytes() : regularBytes;
    final semiBoldBytes = segoeSemiBold.existsSync() ? await segoeSemiBold.readAsBytes() : boldBytes;
    final symBytes = segoeSymbol.existsSync() ? await segoeSymbol.readAsBytes() : null;

    for (final family in [
      'Roboto',
      'Plus Jakarta Sans',
      'PlusJakartaSans',
      'PlusJakartaSans_regular',
      'PlusJakartaSans_600',
      'PlusJakartaSans_700',
      'PlusJakartaSans_800',
      'Inter',
      '.SF UI Text',
      '.SF UI Display',
    ]) {
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.sublistView(regularBytes)));
      loader.addFont(Future.value(ByteData.sublistView(semiBoldBytes)));
      loader.addFont(Future.value(ByteData.sublistView(boldBytes)));
      if (symBytes != null) {
        loader.addFont(Future.value(ByteData.sublistView(symBytes)));
      }
      await loader.load();
    }
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter';
  final materialIconsCandidates = [
    File('$flutterRoot\\bin\\cache\\artifacts\\material_fonts\\MaterialIcons-Regular.otf'),
    File(r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf'),
    File(r'C:\Users\ADMIN\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf'),
    File(r'C:\Users\ADMIN\fvm\default\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf'),
  ];
  for (final candidate in materialIconsCandidates) {
    if (candidate.existsSync()) {
      final iconBytes = await candidate.readAsBytes();
      final iconLoader = FontLoader('MaterialIcons');
      iconLoader.addFont(Future.value(ByteData.sublistView(iconBytes)));
      await iconLoader.load();
      break;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealSystemFontsForScreenshots();
  });

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

  final docEnglishHindiGeneral = DoctorModel(
    id: 'doc-lang-1',
    userId: 'usr-lang-1',
    name: 'Dr. Ananya Rao',
    specialty: 'General Dentist',
    qualification: 'BDS, MDS',
    experienceYears: 8,
    rating: 4.9,
    reviewCount: 64,
    clinicName: 'Bandra West Dental Clinic',
    phone: '9876543211',
    email: 'ananya@gshealth.com',
    status: 'Available',
    city: 'Mumbai',
    pincode: '400050',
    clinicAddress: 'Bandra West, Mumbai',
    languages: const ['English', 'Hindi'],
    nextAvailableSlots: const ['10:00 AM', '11:30 AM'],
    consultationFee: '₹500',
  );

  final docTeluguOrthodontist = DoctorModel(
    id: 'doc-lang-2',
    userId: 'usr-lang-2',
    name: 'Dr. Vikram Reddy',
    specialty: 'Orthodontist',
    qualification: 'BDS, MDS (Orthodontics)',
    experienceYears: 10,
    rating: 5.0,
    reviewCount: 92,
    clinicName: 'GS HEALTH Smile Studio',
    phone: '9876543212',
    email: 'vikram@gshealth.com',
    status: 'Available',
    city: 'Hyderabad',
    pincode: '500033',
    clinicAddress: 'Jubilee Hills, Hyderabad',
    languages: const ['Telugu', 'English'],
    nextAvailableSlots: const ['09:30 AM', '04:00 PM'],
    consultationFee: '₹700',
  );

  final docHindiOrthodontist = DoctorModel(
    id: 'doc-lang-3',
    userId: 'usr-lang-3',
    name: 'Dr. Neha Verma',
    specialty: 'Orthodontist',
    qualification: 'BDS, MDS (Orthodontics)',
    experienceYears: 7,
    rating: 4.8,
    reviewCount: 41,
    clinicName: 'Delhi Aligners Clinic',
    phone: '9876543213',
    email: 'neha@gshealth.com',
    status: 'Available',
    city: 'Delhi',
    pincode: '110001',
    clinicAddress: 'Connaught Place, New Delhi',
    languages: const ['Hindi'],
    nextAvailableSlots: const ['11:00 AM', '02:30 PM'],
    consultationFee: '₹650',
  );

  final docTamilKannada = DoctorModel(
    id: 'doc-lang-4',
    userId: 'usr-lang-4',
    name: 'Dr. Karthik Subramanian',
    specialty: 'Endodontist',
    qualification: 'BDS, MDS (Endodontics)',
    experienceYears: 9,
    rating: 4.9,
    reviewCount: 53,
    clinicName: 'South Care Dental Hub',
    phone: '9876543214',
    email: 'karthik@gshealth.com',
    status: 'Available',
    city: 'Bengaluru',
    pincode: '560001',
    clinicAddress: 'MG Road, Bengaluru',
    languages: const ['Tamil', 'Kannada'],
    nextAvailableSlots: const ['10:30 AM', '05:00 PM'],
    consultationFee: '₹600',
  );

  group('GS HEALTH Find Doctors — Multi-Select Language Filter & Combined Filtering Tests', () {
    testWidgets(
      '1. Filter by Language fetches languages from registered doctors, supports multi-select OR matching, and clears cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(430, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(docEnglishHindiGeneral);
        service.addTestDoctor(docTeluguOrthodontist);
        service.addTestDoctor(docHindiOrthodontist);
        service.addTestDoctor(docTamilKannada);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const FindDoctorsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify Specialty filter row and Language filter row exist and Language row is directly below Specialty row
        final specialtyRowFinder = find.byKey(const Key('specialty_filter_scroll_view'));
        final languageRowFinder = find.byKey(const Key('language_filter_scroll_view'));
        expect(specialtyRowFinder, findsOneWidget);
        expect(languageRowFinder, findsOneWidget);
        expect(find.byKey(const Key('filter_by_language_dropdown')), findsOneWidget);

        final specRect = tester.getRect(specialtyRowFinder);
        final langRect = tester.getRect(languageRowFinder);
        expect(langRect.top, greaterThanOrEqualTo(specRect.bottom));

        // Languages shown come from registered doctors (English, Hindi, Telugu, Tamil, Kannada)
        // Languages NOT spoken by any registered doctor (e.g. Malayalam) are not shown
        expect(find.byKey(const Key('language_filter_chip_Any language')), findsOneWidget);
        expect(find.byKey(const Key('language_filter_chip_English')), findsOneWidget);
        expect(find.byKey(const Key('language_filter_chip_Hindi')), findsOneWidget);
        expect(find.byKey(const Key('language_filter_chip_Telugu')), findsOneWidget);
        expect(find.byKey(const Key('language_filter_chip_Tamil')), findsOneWidget);
        expect(find.byKey(const Key('language_filter_chip_Kannada')), findsOneWidget);
        expect(find.byKey(const Key('language_filter_chip_Malayalam')), findsNothing);

        // Initially "Any language" is selected -> all 4 doctors are shown
        expect(find.text('Dr. Ananya Rao'), findsOneWidget);
        expect(find.text('Dr. Vikram Reddy'), findsOneWidget);
        expect(find.text('Dr. Neha Verma'), findsOneWidget);
        expect(find.text('Dr. Karthik Subramanian'), findsOneWidget);

        // 1) Select single language "English" -> Ananya & Vikram
        await tester.tap(find.byKey(const Key('language_filter_chip_English')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Ananya Rao'), findsOneWidget);
        expect(find.text('Dr. Vikram Reddy'), findsOneWidget);
        expect(find.text('Dr. Neha Verma'), findsNothing);
        expect(find.text('Dr. Karthik Subramanian'), findsNothing);

        // 2) Multi-select: ALSO select "Tamil" -> shows doctors speaking English OR Tamil (Ananya, Vikram, Karthik)
        await tester.ensureVisible(find.byKey(const Key('language_filter_chip_Tamil')));
        await tester.tap(find.byKey(const Key('language_filter_chip_Tamil')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Ananya Rao'), findsOneWidget);
        expect(find.text('Dr. Vikram Reddy'), findsOneWidget);
        expect(find.text('Dr. Karthik Subramanian'), findsOneWidget);
        expect(find.text('Dr. Neha Verma'), findsNothing);

        // 3) Clear language filter via clear button -> restores all 4 doctors
        await tester.tap(find.byKey(const Key('clear_language_filter_button')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Ananya Rao'), findsOneWidget);
        expect(find.text('Dr. Vikram Reddy'), findsOneWidget);
        expect(find.text('Dr. Neha Verma'), findsOneWidget);
        expect(find.text('Dr. Karthik Subramanian'), findsOneWidget);

        // 4) Open multi-select "Filter by Language" dropdown dialog and select Hindi & Telugu
        await tester.tap(find.byKey(const Key('filter_by_language_dropdown')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('language_multiselect_dialog')), findsOneWidget);

        await tester.tap(find.byKey(const Key('language_checkbox_Hindi')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('language_checkbox_Telugu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('language_multiselect_done_btn')));
        await tester.pumpAndSettle();

        // Doctors speaking Hindi OR Telugu (Ananya, Vikram, Neha) shown; Karthik (Tamil, Kannada) excluded
        expect(find.text('Dr. Ananya Rao'), findsOneWidget);
        expect(find.text('Dr. Vikram Reddy'), findsOneWidget);
        expect(find.text('Dr. Neha Verma'), findsOneWidget);
        expect(find.text('Dr. Karthik Subramanian'), findsNothing);

        // Select "Any language" -> restores all 4 doctors
        await tester.drag(languageRowFinder, const Offset(300, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('language_filter_chip_Any language')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Ananya Rao'), findsOneWidget);
        expect(find.text('Dr. Vikram Reddy'), findsOneWidget);
        expect(find.text('Dr. Neha Verma'), findsOneWidget);
        expect(find.text('Dr. Karthik Subramanian'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Specialty + Language + City + Pincode + Availability work together and clearing Language preserves remaining filters',
      (tester) async {
        tester.view.physicalSize = const Size(430, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final docUnavailableHindi = DoctorModel(
          id: 'doc-lang-off',
          userId: 'usr-lang-off',
          name: 'Dr. Offline Doc',
          specialty: 'Orthodontist',
          qualification: 'BDS, MDS',
          experienceYears: 5,
          rating: 4.5,
          reviewCount: 10,
          clinicName: 'Offline Ortho Hub',
          phone: '9876543299',
          email: 'off@gshealth.com',
          status: 'Unavailable',
          city: 'Delhi',
          pincode: '110001',
          clinicAddress: 'Delhi',
          languages: const ['Hindi'],
          nextAvailableSlots: const [],
          consultationFee: '₹500',
        );

        final service = PatientProblemService();
        service.addTestDoctor(docEnglishHindiGeneral);
        service.addTestDoctor(docTeluguOrthodontist);
        service.addTestDoctor(docHindiOrthodontist);
        service.addTestDoctor(docTamilKannada);
        service.addTestDoctor(docUnavailableHindi);
        service.currentPatient.name = 'Anu';
        service.currentPatient.phone = '9876543210';
        service.currentPatient.city = 'Mumbai';
        service.currentPatient.pincode = '400050';
        service.currentPatient.languages = ['English', 'Hindi'];

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const FindDoctorsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Unavailable doctor is never shown even before filters
        expect(find.text('Dr. Offline Doc'), findsNothing);

        // 1) Specialty = Orthodontist -> shows Vikram (Telugu, English) and Neha (Hindi)
        await tester.ensureVisible(find.byKey(const Key('specialty_chip_Orthodontist')));
        await tester.tap(find.byKey(const Key('specialty_chip_Orthodontist')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Vikram Reddy'), findsOneWidget);
        expect(find.text('Dr. Neha Verma'), findsOneWidget);
        expect(find.text('Dr. Ananya Rao'), findsNothing);

        // 2) Add Language = Telugu while Specialty = Orthodontist -> shows ONLY Vikram Reddy
        await tester.ensureVisible(find.byKey(const Key('language_filter_chip_Telugu')));
        await tester.tap(find.byKey(const Key('language_filter_chip_Telugu')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Vikram Reddy'), findsOneWidget);
        expect(find.text('Dr. Neha Verma'), findsNothing);
        expect(find.text('Dr. Ananya Rao'), findsNothing);

        // 3) Selecting "Any language" removes only the language restriction without resetting Orthodontist specialty
        await tester.ensureVisible(find.byKey(const Key('language_filter_chip_Any language')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('language_filter_chip_Any language')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Vikram Reddy'), findsOneWidget);
        expect(find.text('Dr. Neha Verma'), findsOneWidget);
        expect(find.text('Dr. Ananya Rao'), findsNothing);

        // Reset Specialty to "All"
        await tester.ensureVisible(find.byKey(const Key('specialty_chip_All')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('specialty_chip_All')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Ananya Rao'), findsOneWidget);

        // 4) City + Pincode + Language combination: City=Delhi, Pincode=110001, Language=Hindi -> ONLY Dr. Neha Verma (Offline Doc excluded)
        await tester.ensureVisible(find.byKey(const Key('filter_city_input')));
        await tester.enterText(find.byKey(const Key('filter_city_input')), 'Delhi');
        await tester.ensureVisible(find.byKey(const Key('filter_pincode_input')));
        await tester.enterText(find.byKey(const Key('filter_pincode_input')), '110001');
        await tester.ensureVisible(find.byKey(const Key('language_filter_chip_Hindi')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('language_filter_chip_Hindi')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Neha Verma'), findsOneWidget);
        expect(find.text('Dr. Ananya Rao'), findsNothing);
        expect(find.text('Dr. Offline Doc'), findsNothing);

        // Clear City & Pincode
        await tester.ensureVisible(find.byKey(const Key('filter_city_input')));
        await tester.enterText(find.byKey(const Key('filter_city_input')), '');
        await tester.ensureVisible(find.byKey(const Key('filter_pincode_input')));
        await tester.enterText(find.byKey(const Key('filter_pincode_input')), '');
        await tester.pumpAndSettle();

        // 5) Location ("Use my location") + Language combination:
        // Patient's location is Mumbai (400050), Language = Hindi -> shows ONLY Dr. Ananya Rao
        await tester.ensureVisible(find.byKey(const Key('use_my_location_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('use_my_location_button')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Ananya Rao'), findsOneWidget);
        expect(find.text('Dr. Neha Verma'), findsNothing);
      },
    );

    testWidgets(
      '3. Responsive mobile layout & horizontal scrolling work with zero overflow on 320px, 360px, 390px, 412px and captures screenshot',
      (tester) async {
        final service = PatientProblemService();
        service.addTestDoctor(docEnglishHindiGeneral);
        service.addTestDoctor(docTeluguOrthodontist);
        service.addTestDoctor(docHindiOrthodontist);
        service.addTestDoctor(docTamilKannada);

        for (final size in [
          const Size(320, 740),
          const Size(360, 800),
          const Size(390, 844),
          const Size(412, 915),
        ]) {
          await tester.binding.setSurfaceSize(size);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                home: const FindDoctorsScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'No overflow on $size');

          // Scroll language row horizontally on narrow screens
          await tester.drag(find.byKey(const Key('language_filter_scroll_view')), const Offset(-220, 0));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        // Capture screenshot of the Patient Dashboard -> Find tab on 412x915
        const capSize = Size(412, 915);
        await tester.binding.setSurfaceSize(capSize);
        tester.view.physicalSize = capSize;
        tester.view.devicePixelRatio = 2.0;

        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto', useMaterial3: false),
              home: RepaintBoundary(
                key: boundaryKey,
                child: const PatientDashboardScreen(),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        // Switch to "Find" tab in BottomNavigationBar
        await tester.tap(find.text('Find'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          final outFile = File(
            r'C:\Users\ADMIN\.gemini\antigravity\brain\0cdf62c7-364d-4c39-8424-4bae41245b5b\gs_health_find_doctors_language_filter.png',
          );
          await outFile.writeAsBytes(byteData!.buffer.asUint8List());
          expect(outFile.existsSync(), isTrue);
        });

        await tester.binding.setSurfaceSize(null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );
  });
}
