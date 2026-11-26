import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/theme/app_theme.dart';
import 'package:dentaguru/core/utils/clinic_directions_helper.dart';
import 'package:dentaguru/core/widgets/map_location_picker_dialog.dart';
import 'package:dentaguru/features/auth/presentation/screens/auth_screen.dart';
import 'package:dentaguru/features/dentist/presentation/screens/doctor_profile_screen.dart' as dentist_ui;
import 'package:dentaguru/features/patient/presentation/screens/doctor_profile_screen.dart' as patient_ui;
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

GoRouter _buildTestRouter(Widget home) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => home),
      GoRoute(path: '/dentist', builder: (_, __) => const Scaffold(body: Center(child: Text('DENTIST_HOME')))),
      GoRoute(path: '/patient', builder: (_, __) => const Scaffold(body: Center(child: Text('PATIENT_HOME')))),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    OsmMapConfig.debugTileProviderOverride = OfflinePlaceholderTileProvider();
    ClinicDirectionsHelper.debugLaunchUriOverride = null;
    MapLocationPickerDialog.debugSearchOverride = null;
    ApiService.debugRegisterOverride = null;
    ApiService.debugLastRegisterPayload = null;
    ApiService.debugUpdateDoctorProfileOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllDataAndStorage();
  });

  tearDown(() async {
    OsmMapConfig.debugTileProviderOverride = null;
    ClinicDirectionsHelper.debugLaunchUriOverride = null;
    MapLocationPickerDialog.debugSearchOverride = null;
    ApiService.debugRegisterOverride = null;
    ApiService.debugLastRegisterPayload = null;
    ApiService.debugUpdateDoctorProfileOverride = null;
  });

  group('GS HEALTH – Doctor Clinic Registration, OSM Map & Directions Tests', () {
    test('1. ClinicDirectionsHelper builds coordinate URI, address fallback URI, and hides for ONLINE_ONLY', () {
      final coordUri = ClinicDirectionsHelper.buildDirectionsUri(
        consultationMode: DoctorConsultationMode.both,
        latitude: 19.076090,
        longitude: 72.877426,
        clinicName: 'Bandra Dental Studio',
        clinicAddress: 'Hill Road, Bandra West',
        city: 'Mumbai',
      );
      expect(coordUri, isNotNull);
      expect(coordUri.toString(), contains('19.076090'));
      expect(coordUri.toString(), contains('72.877426'));

      final addressFallbackUri = ClinicDirectionsHelper.buildDirectionsUri(
        consultationMode: DoctorConsultationMode.inPerson,
        latitude: null,
        longitude: null,
        clinicName: 'Pearl Care Clinic',
        clinicAddress: '12 MG Road',
        city: 'Bengaluru',
        state: 'Karnataka',
        pincode: '560001',
      );
      expect(addressFallbackUri, isNotNull);
      expect(Uri.decodeFull(addressFallbackUri.toString()), contains('Pearl Care Clinic'));
      expect(Uri.decodeFull(addressFallbackUri.toString()), contains('12 MG Road'));
      expect(Uri.decodeFull(addressFallbackUri.toString()), contains('560001'));

      final onlineOnlyUri = ClinicDirectionsHelper.buildDirectionsUri(
        consultationMode: DoctorConsultationMode.onlineOnly,
        latitude: 19.076090,
        longitude: 72.877426,
        clinicName: 'Should Be Ignored',
        clinicAddress: 'Some Street',
      );
      expect(onlineOnlyUri, isNull);

      final emptyUri = ClinicDirectionsHelper.buildDirectionsUri(
        consultationMode: DoctorConsultationMode.both,
      );
      expect(emptyUri, isNull);
    });

    testWidgets('2. Doctor Registration defaults to BOTH, validates manual clinic details, supports OSM map picker & Remove Pin', (tester) async {
      tester.view.physicalSize = const Size(412, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      int registerCalls = 0;
      ApiService.debugRegisterOverride = ({
        required String name,
        required String phone,
        String? email,
        String? password,
        String role = 'Patient',
        String? age,
        String? gender,
        String? bloodGroup,
        String? emergencyContact,
        String? specialty,
        String? licenseNumber,
        String? clinicId,
        String? clinicName,
        String? clinicAddress,
        String? consultationFee,
        String? bio,
        String? location,
        String? state,
        String? city,
        String? pincode,
        double? latitude,
        double? longitude,
        String? qualification,
        int? experienceYears,
        String? profilePhoto,
        List<String>? languages,
        String? referralCode,
      }) async {
        registerCalls++;
        return {
          'success': true,
          'token': 'doc-test-jwt',
          'user': {
            'id': 'doc-osm-1',
            'name': name,
            'phone': phone,
            'role': role,
            'clinicName': clinicName,
          },
        };
      };

      MapLocationPickerDialog.debugSearchOverride = (query) async => [
            {
              'display_name': 'Hill Road, Bandra West, Mumbai, Maharashtra, 400050',
              'lat': '19.054440',
              'lon': '72.830020',
              'address': {
                'city': 'Mumbai',
                'state': 'Maharashtra',
                'postcode': '400050',
              },
            },
          ];

      final router = _buildTestRouter(
        const AuthScreen(
          initialTab: 0,
          initialRole: 'dentist',
          initialVerifiedPhone: '9876543210',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default is BOTH -> clinic fields & map picker button visible
      expect(find.byKey(const Key('reg_dentist_clinic_name_field')), findsOneWidget);
      expect(find.byKey(const Key('reg_dentist_clinic_address_field')), findsOneWidget);
      expect(find.byKey(const Key('reg_dentist_state_field')), findsOneWidget);
      expect(find.byKey(const Key('reg_dentist_pincode_field')), findsOneWidget);
      expect(find.byKey(const Key('reg_open_map_picker_button')), findsOneWidget);

      // Attempting submit with Name + City but missing Clinic Name & Address triggers validation
      await tester.enterText(find.byKey(const Key('reg_full_name_field')), 'Dr. Kavita Mehta');
      await tester.enterText(find.byKey(const Key('reg_city_field')), 'Mumbai');
      final continueBtn = find.byKey(const Key('reg_continue_button'));
      await tester.drag(find.byKey(const Key('registration_scroll_view')), const Offset(0, -1800));
      await tester.pumpAndSettle();
      await tester.ensureVisible(continueBtn);
      await tester.pumpAndSettle();
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter clinic name'), findsOneWidget);
      expect(find.text('Please enter clinic address'), findsOneWidget);
      expect(registerCalls, 0);

      // Enter clinic name manually and pick location via OpenStreetMap dialog
      await tester.ensureVisible(find.byKey(const Key('reg_dentist_clinic_name_field')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reg_dentist_clinic_name_field')), 'Bandra Smile Clinic');

      final openMapBtn = find.byKey(const Key('reg_open_map_picker_button'));
      await tester.ensureVisible(openMapBtn);
      await tester.pumpAndSettle();
      await tester.tap(openMapBtn);
      await tester.pumpAndSettle();

      // OSM dialog renders FlutterMap and mandatory attribution
      expect(find.byKey(const Key('osm_location_picker_dialog')), findsOneWidget);
      expect(find.byKey(const Key('osm_flutter_map')), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

      // Search & select mocked OSM place
      await tester.enterText(find.byKey(const Key('osm_picker_search_field')), 'Bandra West');
      await tester.tap(find.byKey(const Key('osm_picker_search_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('osm_search_result_0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('osm_search_result_0')));
      await tester.pumpAndSettle();

      // Confirm location
      await tester.tap(find.byKey(const Key('osm_picker_confirm_btn')));
      await tester.pumpAndSettle();

      // Preview card with Change Location & Remove Pin appears
      expect(find.byKey(const Key('osm_preview_change_location_btn')), findsOneWidget);
      expect(find.byKey(const Key('osm_preview_remove_location_btn')), findsOneWidget);

      // Submit registration
      await tester.drag(find.byKey(const Key('registration_scroll_view')), const Offset(0, -1800));
      await tester.pumpAndSettle();
      await tester.ensureVisible(continueBtn);
      await tester.pumpAndSettle();
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();

      expect(registerCalls, 1);
      expect(ApiService.debugLastRegisterPayload?['consultationMode'], 'BOTH');
      expect(ApiService.debugLastRegisterPayload?['clinicName'], 'Bandra Smile Clinic');
      expect(ApiService.debugLastRegisterPayload?['clinicAddress'], contains('Hill Road'));
      expect(ApiService.debugLastRegisterPayload?['state'], 'Maharashtra');
      expect(ApiService.debugLastRegisterPayload?['pincode'], '400050');
      expect(ApiService.debugLastRegisterPayload?['latitude'], closeTo(19.05444, 0.001));
      expect(ApiService.debugLastRegisterPayload?['longitude'], closeTo(72.83002, 0.001));
      expect(find.text('DENTIST_HOME'), findsOneWidget);
    });

    testWidgets('3. Doctor Profile displays clinic address/OSM pin and persists Edit Clinic Details updates', (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? capturedUpdatePayload;
      ApiService.debugUpdateDoctorProfileOverride = (doctorId, updates) async {
        capturedUpdatePayload = updates;
        return {'success': true, 'doctor': {'id': doctorId, ...updates}};
      };

      final service = PatientProblemService();
      final doc = DoctorModel(
        id: 'doc-profile-loc-1',
        userId: 'usr-profile-loc-1',
        name: 'Dr. Rohan Deshmukh',
        specialty: 'Orthodontics',
        qualification: 'BDS, MDS',
        experienceYears: 10,
        rating: 4.8,
        reviewCount: 25,
        clinicName: 'Deccan Dental Care',
        clinicAddress: 'FC Road, Shivajinagar',
        city: 'Pune',
        state: 'Maharashtra',
        pincode: '411004',
        latitude: 18.52043,
        longitude: 73.85674,
        consultationMode: DoctorConsultationMode.both,
        phone: '+919822001122',
        email: 'rohan@gshealth.in',
        status: 'Available',
        nextAvailableSlots: const ['Today, 4:00 PM'],
        consultationFee: '₹700',
      );
      service.currentDoctor = doc;
      service.addTestDoctor(doc);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: dentist_ui.DoctorProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Displays clinic name, address, city/state/pincode, and OSM preview
      expect(find.byKey(const Key('doctor_profile_clinic_name_text')), findsOneWidget);
      expect(find.text('Deccan Dental Care'), findsAtLeastNWidgets(1));
      expect(find.text('FC Road, Shivajinagar'), findsOneWidget);
      expect(find.text('Pune, Maharashtra, 411004'), findsOneWidget);
      expect(find.byKey(const Key('doctor_profile_osm_preview')), findsOneWidget);

      // Tap Edit clinic details
      final editClinicBtn = find.byKey(const Key('doctor_profile_edit_clinic_button'));
      await tester.ensureVisible(editClinicBtn);
      await tester.tap(editClinicBtn);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('edit_doctor_clinic_address_field')), 'JM Road, Deccan Gymkhana');
      await tester.enterText(find.byKey(const Key('edit_doctor_pincode_field')), '411005');

      final saveBtn = find.byKey(const Key('save_doctor_profile_button'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(capturedUpdatePayload?['clinicAddress'], 'JM Road, Deccan Gymkhana');
      expect(capturedUpdatePayload?['pincode'], '411005');
      expect(capturedUpdatePayload?['state'], 'Maharashtra');
      expect(capturedUpdatePayload?['latitude'], closeTo(18.52043, 0.001));
      expect(service.currentDoctor?.clinicAddress, 'JM Road, Deccan Gymkhana');
      expect(service.currentDoctor?.pincode, '411005');
    });

    testWidgets('4. Patient Find Doctors & Doctor Details show Directions (coords & address fallback) and hide for ONLINE_ONLY', (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final launchedUris = <Uri>[];
      ClinicDirectionsHelper.debugLaunchUriOverride = (uri) async {
        launchedUris.add(uri);
        return true;
      };

      final service = PatientProblemService();
      final docWithPin = DoctorModel(
        id: 'doc-pin',
        name: 'Dr. Meera Nair',
        specialty: 'General Dentistry',
        qualification: 'BDS',
        experienceYears: 7,
        rating: 4.9,
        reviewCount: 15,
        clinicName: 'Indiranagar Dental Studio',
        clinicAddress: '100 Feet Road, Indiranagar',
        city: 'Bengaluru',
        state: 'Karnataka',
        pincode: '560038',
        latitude: 12.978369,
        longitude: 77.640836,
        consultationMode: DoctorConsultationMode.both,
        phone: '+919900112233',
        email: 'meera@gshealth.in',
        status: 'Available',
        nextAvailableSlots: const ['Today, 3:00 PM'],
        consultationFee: '₹600',
      );
      final docManualOnly = DoctorModel(
        id: 'doc-manual',
        name: 'Dr. Arjun Singh',
        specialty: 'Orthodontics',
        qualification: 'BDS, MDS',
        experienceYears: 9,
        rating: 4.7,
        reviewCount: 12,
        clinicName: 'Connaught Dental Clinic',
        clinicAddress: 'Block B, Connaught Place',
        city: 'New Delhi',
        state: 'Delhi',
        pincode: '110001',
        consultationMode: DoctorConsultationMode.inPerson,
        phone: '+919900112244',
        email: 'arjun@gshealth.in',
        status: 'Available',
        nextAvailableSlots: const ['Tomorrow, 11:00 AM'],
        consultationFee: '₹800',
      );
      final docOnlineOnly = DoctorModel(
        id: 'doc-online',
        name: 'Dr. Sneha Kapoor',
        specialty: 'General Medicine',
        qualification: 'MBBS, MD',
        experienceYears: 6,
        rating: 4.8,
        reviewCount: 20,
        clinicName: '',
        clinicAddress: '',
        city: 'Mumbai',
        consultationMode: DoctorConsultationMode.onlineOnly,
        phone: '+919900112255',
        email: 'sneha@gshealth.in',
        status: 'Available',
        nextAvailableSlots: const ['Today, 5:00 PM'],
        consultationFee: '₹500',
      );

      service.addTestDoctor(docWithPin);
      service.addTestDoctor(docManualOnly);
      service.addTestDoctor(docOnlineOnly);

      // A. Find Doctors listing
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: FindDoctorsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('doctor_card_directions_doc-pin')), findsOneWidget);
      expect(find.byKey(const Key('doctor_card_directions_doc-manual')), findsOneWidget);
      expect(find.byKey(const Key('doctor_card_directions_doc-online')), findsNothing);
      expect(find.byKey(const Key('doctor_online_only_badge_doc-online')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('doctor_card_directions_doc-pin')));
      await tester.tap(find.byKey(const Key('doctor_card_directions_doc-pin')));
      await tester.pump();
      expect(launchedUris.length, 1);
      expect(launchedUris.last.toString(), contains('12.978369'));

      await tester.ensureVisible(find.byKey(const Key('doctor_card_directions_doc-manual')));
      await tester.tap(find.byKey(const Key('doctor_card_directions_doc-manual')));
      await tester.pump();
      expect(launchedUris.length, 2);
      expect(Uri.decodeFull(launchedUris.last.toString()), contains('Connaught Dental Clinic'));

      // B. Patient Doctor Details for doctor WITH coordinates
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: patient_ui.DoctorProfileScreen(doctor: docWithPin)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('patient_doctor_osm_preview')), findsOneWidget);
      expect(find.byKey(const Key('patient_doctor_directions_button')), findsOneWidget);
      expect(find.text('Get Directions (Map Pin)'), findsOneWidget);

      // C. Patient Doctor Details for ONLINE_ONLY doctor (no fake clinic, no Directions)
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: patient_ui.DoctorProfileScreen(doctor: docOnlineOnly)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('patient_doctor_online_only_card')), findsOneWidget);
      expect(find.byKey(const Key('patient_doctor_directions_button')), findsNothing);
      expect(find.byKey(const Key('patient_doctor_osm_preview')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
