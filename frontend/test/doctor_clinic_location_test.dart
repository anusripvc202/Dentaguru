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
    OsmMapConfig.debugSimulateNetworkError = false;
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
    OsmMapConfig.debugSimulateNetworkError = false;
    ClinicDirectionsHelper.debugLaunchUriOverride = null;
    MapLocationPickerDialog.debugSearchOverride = null;
    ApiService.debugRegisterOverride = null;
    ApiService.debugLastRegisterPayload = null;
    ApiService.debugUpdateDoctorProfileOverride = null;
  });

  group('GS HEALTH – Doctor Clinic Registration, OSM Map & Get Directions Tests', () {
    test('1. ClinicDirectionsHelper builds Google Maps coordinate URI, address fallback URI, and validates bounds', () {
      expect(ClinicDirectionsHelper.hasValidCoordinates(19.076090, 72.877426), isTrue);
      expect(ClinicDirectionsHelper.hasValidCoordinates(95.0, 72.0), isFalse);
      expect(ClinicDirectionsHelper.hasValidCoordinates(19.0, 190.0), isFalse);
      expect(ClinicDirectionsHelper.hasValidCoordinates(null, 72.0), isFalse);
      expect(ClinicDirectionsHelper.isValidPincode('400050'), isTrue);
      expect(ClinicDirectionsHelper.isValidPincode('4000'), isFalse);

      final coordUri = ClinicDirectionsHelper.buildDirectionsUri(
        latitude: 19.076090,
        longitude: 72.877426,
        clinicName: 'Bandra Dental Studio',
        clinicAddress: 'Hill Road, Bandra West',
        city: 'Mumbai',
      );
      expect(coordUri, isNotNull);
      expect(coordUri.toString(), contains('google.com/maps/dir'));
      expect(coordUri.toString(), contains('19.076090'));
      expect(coordUri.toString(), contains('72.877426'));

      final addressFallbackUri = ClinicDirectionsHelper.buildDirectionsUri(
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
      expect(Uri.decodeFull(addressFallbackUri.toString()), contains('Karnataka'));
      expect(Uri.decodeFull(addressFallbackUri.toString()), contains('560001'));

      final emptyUri = ClinicDirectionsHelper.buildDirectionsUri();
      expect(emptyUri, isNull);
    });

    testWidgets('2. Doctor Registration validates clinic fields, pincode & mandatory map pin, supports tap/drag/zoom OSM picker', (tester) async {
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

      // Must NOT render Consultation Type or Online/In-Person options
      expect(find.text('CONSULTATION TYPE'), findsNothing);
      expect(find.text('Online Only'), findsNothing);
      expect(find.byKey(const Key('reg_consultation_mode_selector')), findsNothing);

      // All 6 clinic registration elements present
      expect(find.byKey(const Key('reg_dentist_clinic_name_field')), findsOneWidget);
      expect(find.byKey(const Key('reg_dentist_clinic_address_field')), findsOneWidget);
      expect(find.byKey(const Key('reg_city_field')), findsOneWidget);
      expect(find.byKey(const Key('reg_dentist_state_field')), findsOneWidget);
      expect(find.byKey(const Key('reg_dentist_pincode_field')), findsOneWidget);
      expect(find.byKey(const Key('reg_open_map_picker_button')), findsOneWidget);
      expect(find.text('Select Clinic Location'), findsOneWidget);

      // Attempt submit with missing fields + invalid pincode + missing map pin
      await tester.enterText(find.byKey(const Key('reg_full_name_field')), 'Dr. Kavita Mehta');
      await tester.enterText(find.byKey(const Key('reg_city_field')), 'Mumbai');
      await tester.ensureVisible(find.byKey(const Key('reg_dentist_pincode_field')));
      await tester.enterText(find.byKey(const Key('reg_dentist_pincode_field')), '4000');

      final continueBtn = find.byKey(const Key('reg_continue_button'));
      await tester.drag(find.byKey(const Key('registration_scroll_view')), const Offset(0, -1800));
      await tester.pumpAndSettle();
      await tester.ensureVisible(continueBtn);
      await tester.pumpAndSettle();
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter clinic name'), findsOneWidget);
      expect(find.text('Please enter clinic address'), findsOneWidget);
      expect(find.text('Please enter state'), findsOneWidget);
      expect(find.text('Enter 6-digit pincode'), findsOneWidget);
      expect(find.byKey(const Key('reg_dentist_map_error')), findsOneWidget);
      expect(registerCalls, 0);

      // Fill required clinic details
      await tester.ensureVisible(find.byKey(const Key('reg_dentist_clinic_name_field')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reg_dentist_clinic_name_field')), 'Bandra Smile Clinic');
      await tester.enterText(find.byKey(const Key('reg_dentist_clinic_address_field')), 'Hill Road, Bandra West');
      await tester.enterText(find.byKey(const Key('reg_dentist_state_field')), 'Maharashtra');
      await tester.enterText(find.byKey(const Key('reg_dentist_pincode_field')), '400050');

      // Open OpenStreetMap picker
      final openMapBtn = find.byKey(const Key('reg_open_map_picker_button'));
      await tester.ensureVisible(openMapBtn);
      await tester.pumpAndSettle();
      await tester.tap(openMapBtn);
      await tester.pumpAndSettle();

      // Verify NO hardcoded Hyderabad coords pre-selected; real FlutterMap + OSM attribution shown
      expect(find.byKey(const Key('osm_location_picker_dialog')), findsOneWidget);
      expect(find.byKey(const Key('osm_flutter_map')), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.text('Tap on the map to place clinic marker'), findsOneWidget);
      expect(find.textContaining('17.3850'), findsNothing);

      // Tapping Select Clinic Location before dropping a pin shows inline error
      await tester.tap(find.byKey(const Key('osm_picker_confirm_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('osm_picker_selection_error')), findsOneWidget);

      // Tap map to drop marker, test zoom controls, and drag marker to fine-tune
      await tester.tap(find.byKey(const Key('osm_flutter_map')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('osm_draggable_marker')), findsOneWidget);
      await tester.tap(find.byKey(const Key('osm_zoom_in_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('osm_zoom_out_btn')));
      await tester.pumpAndSettle();

      final coordsBeforeDrag = tester.widget<Text>(
        find.descendant(of: find.byKey(const Key('osm_live_coords_pill')), matching: find.byType(Text)),
      ).data;
      await tester.drag(find.byKey(const Key('osm_draggable_marker')), const Offset(28, -22));
      await tester.pumpAndSettle();
      final coordsAfterDrag = tester.widget<Text>(
        find.descendant(of: find.byKey(const Key('osm_live_coords_pill')), matching: find.byType(Text)),
      ).data;
      expect(coordsAfterDrag, isNotNull);
      expect(coordsAfterDrag, isNot(equals(coordsBeforeDrag)));

      // Confirm clinic location
      await tester.tap(find.byKey(const Key('osm_picker_confirm_btn')));
      await tester.pumpAndSettle();

      // Preview card appears with coordinates & Change Location
      expect(find.byKey(const Key('osm_preview_change_location_btn')), findsOneWidget);
      expect(find.byKey(const Key('reg_dentist_map_error')), findsNothing);

      // Submit registration (clear any validation SnackBar so Continue button is unobstructed)
      ScaffoldMessenger.of(tester.element(continueBtn)).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const Key('registration_scroll_view')), const Offset(0, -1800));
      await tester.pumpAndSettle();
      await tester.ensureVisible(continueBtn);
      await tester.pumpAndSettle();
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();

      expect(registerCalls, 1);
      expect(ApiService.debugLastRegisterPayload?['clinicName'], 'Bandra Smile Clinic');
      expect(ApiService.debugLastRegisterPayload?['clinicAddress'], 'Hill Road, Bandra West');
      expect(ApiService.debugLastRegisterPayload?['city'], 'Mumbai');
      expect(ApiService.debugLastRegisterPayload?['state'], 'Maharashtra');
      expect(ApiService.debugLastRegisterPayload?['pincode'], '400050');
      expect(ApiService.debugLastRegisterPayload?['latitude'], isNotNull);
      expect(ApiService.debugLastRegisterPayload?['longitude'], isNotNull);
      expect(find.text('DENTIST_HOME'), findsOneWidget);
    });

    testWidgets('3. Map network failure shows graceful banner while keeping manual address editable', (tester) async {
      OsmMapConfig.debugSimulateNetworkError = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  MapLocationPickerDialog.show(
                    context: ctx,
                    initialAddress: '10 Park Street',
                    initialCity: 'Kolkata',
                    initialState: 'West Bengal',
                    initialPincode: '700016',
                  );
                },
                child: const Text('Open Map'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Map'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('osm_map_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('osm_map_retry_btn')), findsOneWidget);
      // Manual address fields remain fully editable despite tile network failure
      await tester.enterText(find.byKey(const Key('osm_picker_address_field')), '22 Park Street, Kolkata');
      expect(find.text('22 Park Street, Kolkata'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Doctor Profile displays saved clinic details, reopens map at saved marker, and saves edits', (tester) async {
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

      // Displays clinic name, address, city/state/pincode, OSM preview, and NO consultation type badge
      expect(find.byKey(const Key('doctor_profile_clinic_name_text')), findsOneWidget);
      expect(find.text('Deccan Dental Care'), findsAtLeastNWidgets(1));
      expect(find.text('FC Road, Shivajinagar'), findsOneWidget);
      expect(find.text('Pune, Maharashtra, 411004'), findsOneWidget);
      expect(find.byKey(const Key('doctor_profile_osm_preview')), findsOneWidget);
      expect(find.byKey(const Key('doctor_profile_consultation_mode_badge')), findsNothing);

      // Tap Edit clinic details
      final editClinicBtn = find.byKey(const Key('doctor_profile_edit_clinic_button'));
      await tester.ensureVisible(editClinicBtn);
      await tester.tap(editClinicBtn);
      await tester.pumpAndSettle();

      // Reopen map picker from Edit sheet -> previously saved marker & coordinates are shown immediately
      final changeLocBtn = find.descendant(
        of: find.byKey(const Key('edit_doctor_osm_preview')),
        matching: find.byKey(const Key('osm_preview_change_location_btn')),
      );
      await tester.ensureVisible(changeLocBtn);
      await tester.tap(changeLocBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('osm_draggable_marker')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('osm_live_coords_pill')),
          matching: find.textContaining('18.52043'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('osm_live_coords_pill')),
          matching: find.textContaining('73.85674'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('osm_picker_confirm_btn')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('edit_doctor_clinic_address_field')), 'JM Road, Deccan Gymkhana');
      await tester.enterText(find.byKey(const Key('edit_doctor_pincode_field')), '411005');

      final saveBtn = find.byKey(const Key('save_doctor_profile_button'));
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(capturedUpdatePayload?['clinicAddress'], 'JM Road, Deccan Gymkhana');
      expect(capturedUpdatePayload?['pincode'], '411005');
      expect(capturedUpdatePayload?['state'], 'Maharashtra');
      expect(capturedUpdatePayload?['latitude'], closeTo(18.52043, 0.001));
      expect(service.currentDoctor?.clinicAddress, 'JM Road, Deccan Gymkhana');
      expect(service.currentDoctor?.pincode, '411005');
    });

    testWidgets('5. Patient Find Doctors & Doctor Details display full clinic address, Get Directions, and handle legacy doctors without coordinates', (tester) async {
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
        phone: '+919900112233',
        email: 'meera@gshealth.in',
        status: 'Available',
        nextAvailableSlots: const ['Today, 3:00 PM'],
        consultationFee: '₹600',
      );
      // Existing legacy doctor with address only (no lat/lng saved yet)
      final docLegacyManual = DoctorModel(
        id: 'doc-legacy-manual',
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
        phone: '+919900112244',
        email: 'arjun@gshealth.in',
        status: 'Available',
        nextAvailableSlots: const ['Tomorrow, 11:00 AM'],
        consultationFee: '₹800',
      );
      // Legacy doctor with neither coordinates nor address
      final docLegacyEmpty = DoctorModel(
        id: 'doc-legacy-empty',
        name: 'Dr. Sneha Kapoor',
        specialty: 'General Medicine',
        qualification: 'MBBS, MD',
        experienceYears: 6,
        rating: 4.8,
        reviewCount: 20,
        clinicName: '',
        clinicAddress: '',
        city: '',
        phone: '+919900112255',
        email: 'sneha@gshealth.in',
        status: 'Available',
        nextAvailableSlots: const ['Today, 5:00 PM'],
        consultationFee: '₹500',
      );

      service.addTestDoctor(docWithPin);
      service.addTestDoctor(docLegacyManual);
      service.addTestDoctor(docLegacyEmpty);

      // A. Find Doctors listing
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: FindDoctorsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      expect(find.byKey(const Key('doctor_card_directions_doc-pin')), findsOneWidget);
      expect(find.byKey(const Key('doctor_card_directions_doc-legacy-manual')), findsOneWidget);
      expect(find.byKey(const Key('doctor_card_directions_doc-legacy-empty')), findsNothing);
      expect(find.text('Get Directions'), findsNWidgets(2));
      expect(find.textContaining('Bengaluru, Karnataka, 560038'), findsOneWidget);
      expect(find.text('100 Feet Road, Indiranagar'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('doctor_card_directions_doc-pin')));
      await tester.tap(find.byKey(const Key('doctor_card_directions_doc-pin')));
      await tester.pump();
      expect(launchedUris.length, 1);
      expect(launchedUris.last.toString(), contains('google.com/maps/dir'));
      expect(launchedUris.last.toString(), contains('12.978369'));

      await tester.ensureVisible(find.byKey(const Key('doctor_card_directions_doc-legacy-manual')));
      await tester.tap(find.byKey(const Key('doctor_card_directions_doc-legacy-manual')));
      await tester.pump();
      expect(launchedUris.length, 2);
      expect(Uri.decodeFull(launchedUris.last.toString()), contains('Connaught Dental Clinic'));
      expect(Uri.decodeFull(launchedUris.last.toString()), contains('110001'));

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
      expect(find.text('Get Directions'), findsOneWidget);
      expect(find.text('Map Pin Verified'), findsOneWidget);
      expect(find.text('Bengaluru, Karnataka, 560038'), findsOneWidget);

      // C. Patient Doctor Details for legacy doctor WITHOUT coordinates (no fake map preview; address-based directions work)
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: patient_ui.DoctorProfileScreen(doctor: docLegacyManual)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('patient_doctor_osm_preview')), findsNothing);
      expect(find.byKey(const Key('patient_doctor_directions_button')), findsOneWidget);
      expect(find.text('Address Only'), findsOneWidget);
      expect(find.text('New Delhi, Delhi, 110001'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('6. DoctorModel.fromJson preserves all 7 clinic fields & coordinates and handles legacy doctors with null coords', () {
      final fullDoc = DoctorModel.fromJson({
        'id': 'doc-full-1',
        'user_id': 'usr-full-1',
        'name': 'Dr. Anjali Menon',
        'speciality': 'Periodontics',
        'qualifications': 'BDS, MDS',
        'experience_years': 8,
        'clinicName': 'Marine Drive Dental Care',
        'clinicAddress': '45 Netaji Subhash Road, Marine Drive',
        'city': 'Mumbai',
        'state': 'Maharashtra',
        'pincode': '400020',
        'latitude': 18.94321,
        'longitude': 72.82356,
        'phone': '9820112233',
        'email': 'anjali@gshealth.in',
      });
      expect(fullDoc.clinicName, 'Marine Drive Dental Care');
      expect(fullDoc.clinicAddress, '45 Netaji Subhash Road, Marine Drive');
      expect(fullDoc.city, 'Mumbai');
      expect(fullDoc.state, 'Maharashtra');
      expect(fullDoc.pincode, '400020');
      expect(fullDoc.latitude, 18.94321);
      expect(fullDoc.longitude, 72.82356);
      expect(fullDoc.hasCoordinates, isTrue);

      final legacyDoc = DoctorModel.fromJson({
        'id': 'doc-legacy-1',
        'name': 'Dr. Suresh Kumar',
        'speciality': 'General Dentistry',
        'clinics': {'clinic_name': 'Old Town Dental', 'location': '15 Civil Lines'},
        'city': 'Jaipur',
        'state': 'Rajasthan',
        'pincode': '302006',
      });
      expect(legacyDoc.clinicName, 'Old Town Dental');
      expect(legacyDoc.clinicAddress, '15 Civil Lines');
      expect(legacyDoc.latitude, isNull);
      expect(legacyDoc.longitude, isNull);
      expect(legacyDoc.hasCoordinates, isFalse);
      expect(legacyDoc.hasPhysicalClinicLocation, isTrue);
    });
  });
}
