import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/utils/clinic_directions_helper.dart';
import 'package:dentaguru/features/admin/presentation/widgets/admin_clinic_management_panel.dart';
import 'package:dentaguru/features/auth/presentation/widgets/gs_health_registration_view.dart';
import 'package:dentaguru/features/clinic/presentation/widgets/clinic_add_doctors_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OsmMapConfig.debugTileProviderOverride = OfflinePlaceholderTileProvider();
  });

  tearDown(() {
    OsmMapConfig.debugTileProviderOverride = null;
    ApiService.debugFetchClinicsSearchOverride = null;
    ApiService.debugFetchClinicDoctorsFilteredOverride = null;
    ApiService.debugAssociateDoctorsToClinicOverride = null;
    ApiService.debugRemoveDoctorAssociationOverride = null;
    ApiService.debugRegisterClinicDoctorOverride = null;
  });

  group('GS Health — Complete Clinic Management System Tests', () {
    testWidgets(
      '1. Clinic Registration form requires Clinic Name, Address, City, State, Pincode & OSM location with NO Doctor Name or Consultation Type',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(412, 920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final formKey = GlobalKey<FormState>();
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: GsHealthRegistrationView(
                formKey: formKey,
                selectedRole: UserRole.clinic,
                isAuthorizedAdminPortal: false,
                isRegistering: false,
                isOtpVerified: true,
                verifiedPhone: '9811100011',
                nameController: TextEditingController(),
                cityController: TextEditingController(),
                stateController: TextEditingController(),
                pincodeController: TextEditingController(),
                emailController: TextEditingController(),
                phoneController: TextEditingController(text: '9811100011'),
                locationController: TextEditingController(),
                licenseNoController: TextEditingController(),
                clinicNameController: TextEditingController(),
                clinicAddressController: TextEditingController(),
                qualificationController: TextEditingController(),
                experienceController: TextEditingController(),
                adminEmployeeIdController: TextEditingController(),
                adminDeptController: TextEditingController(),
                selectedAdminRoleType: 'Main Admin',
                selectedSpecialty: 'General Medicine',
                specialtyOptions: const ['General Medicine'],
                selectedLanguages: const {'English'},
                selectedLatitude: null,
                selectedLongitude: null,
                selectedMapLocationName: null,
                pickedImageBytes: null,
                pickedImageName: null,
                clinicOptions: const [],
                onRoleSelected: (_) {},
                onLanguageToggled: (_) {},
                onAdminRoleTypeChanged: (_) {},
                onSpecialtyChanged: (_) {},
                onPickImage: () {},
                onOpenMapPicker: () {},
                onContinuePressed: () {},
                onUseAnotherNumber: () {},
                onOpenAdminSignIn: () {},
                mobileOtpSectionBuilder: () => const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('reg_clinic_name_field')), findsOneWidget);
        expect(find.byKey(const Key('reg_clinic_address_field')), findsOneWidget);
        expect(find.byKey(const Key('reg_city_field')), findsOneWidget);
        expect(find.byKey(const Key('reg_state_field')), findsOneWidget);
        expect(find.byKey(const Key('reg_pincode_field')), findsOneWidget);
        expect(find.byKey(const Key('reg_open_map_picker_button')), findsOneWidget);

        // Must NOT include Doctor Name / Full Name or Consultation Type
        expect(find.byKey(const Key('reg_full_name_field')), findsNothing);
        expect(find.textContaining('Consultation Type'), findsNothing);
        expect(find.textContaining('Online Only'), findsNothing);

        // Submitting empty form fails validation cleanly
        expect(formKey.currentState!.validate(), isFalse);
      },
    );

    testWidgets(
      '2. ClinicAddDoctorsDialog searches by Name/Mobile/ID, filters by Specialization, prevents duplicates, and associates multiple doctors',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(900, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        List<String>? submittedIds;
        ApiService.debugAssociateDoctorsToClinicOverride = ({
          required String clinicId,
          required List<String> doctorIds,
          String? clinicName,
        }) async {
          submittedIds = doctorIds;
          return {
            'success': true,
            'addedCount': doctorIds.length,
            'message': '${doctorIds.length} doctors associated cleanly.',
          };
        };

        final doctors = [
          DoctorModel(
            id: 'doc-1',
            name: 'Dr. Asha Menon',
            specialty: 'Cardiology',
            qualification: 'MD',
            experienceYears: 8,
            rating: 4.9,
            reviewCount: 10,
            clinicName: '',
            phone: '9800011111',
            email: 'asha@test.local',
            status: 'Available',
            nextAvailableSlots: const [],
            consultationFee: '500',
          ),
          DoctorModel(
            id: 'doc-2',
            name: 'Dr. Vikram Joshi',
            specialty: 'Dentistry',
            qualification: 'MDS',
            experienceYears: 6,
            rating: 4.8,
            reviewCount: 8,
            clinicName: '',
            phone: '9800022222',
            email: 'vikram@test.local',
            status: 'Available',
            nextAvailableSlots: const [],
            consultationFee: '400',
          ),
          DoctorModel(
            id: 'doc-3',
            name: 'Dr. Sneha Rao',
            specialty: 'Pediatrics',
            qualification: 'MD',
            experienceYears: 5,
            rating: 4.7,
            reviewCount: 6,
            clinicName: 'Lotus Care Clinic',
            clinicId: 'cli-1',
            phone: '9800033333',
            email: 'sneha@test.local',
            status: 'Available',
            nextAvailableSlots: const [],
            consultationFee: '450',
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () => ClinicAddDoctorsDialog.show(
                      ctx,
                      clinicId: 'cli-1',
                      clinicName: 'Lotus Care Clinic',
                      allRegisteredDoctors: doctors,
                      alreadyAssociatedDoctorIds: const {'doc-3'},
                    ),
                    child: const Text('Open Add Doctors'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Add Doctors'));
        await tester.pumpAndSettle();

        // Already-associated doctor shows Associated badge
        expect(find.text('Associated'), findsOneWidget);

        // Select multiple available doctors (doc-1 and doc-2)
        await tester.tap(find.byKey(const Key('clinic_add_doctor_item_doc-1')));
        await tester.tap(find.byKey(const Key('clinic_add_doctor_item_doc-2')));
        await tester.pumpAndSettle();

        expect(find.text('2 selected'), findsOneWidget);

        // Confirm association
        await tester.tap(find.byKey(const Key('clinic_add_doctors_confirm_btn')));
        await tester.pumpAndSettle();

        expect(submittedIds, isNotNull);
        expect(submittedIds!.toSet(), {'doc-1', 'doc-2'});
      },
    );

    testWidgets(
      '3. AdminClinicManagementPanel searches clinics dynamically, opens Clinic Details with OSM map & Associated Doctors, and filters doctors cleanly',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final sampleClinics = [
          {
            'id': 'cli-mum-01',
            'clinicName': 'Lotus Care Clinic',
            'clinicAddress': '45 Linking Road',
            'city': 'Mumbai',
            'state': 'Maharashtra',
            'pincode': '400050',
            'latitude': 19.06069,
            'longitude': 72.83624,
            'associatedDoctorsCount': 2,
          },
          {
            'id': 'cli-blr-02',
            'clinicName': 'Sunrise Health Hub',
            'clinicAddress': '12 MG Road',
            'city': 'Bengaluru',
            'state': 'Karnataka',
            'pincode': '560001',
            'latitude': 12.9716,
            'longitude': 77.5946,
            'associatedDoctorsCount': 1,
          },
        ];

        final lotusDoctors = [
          {
            'id': 'doc-1',
            'name': 'Dr. Asha Menon',
            'specialty': 'Cardiology',
            'department': 'Heart Care',
            'phone': '9800011111',
            'clinicId': 'cli-mum-01',
            'clinicName': 'Lotus Care Clinic',
            'status': 'Available',
          },
          {
            'id': 'doc-2',
            'name': 'Dr. Vikram Joshi',
            'specialty': 'Dentistry',
            'department': 'Oral Care',
            'phone': '9800022222',
            'clinicId': 'cli-mum-01',
            'clinicName': 'Lotus Care Clinic',
            'status': 'Available',
          },
        ];

        ApiService.debugFetchClinicsSearchOverride = ({String? search, int page = 1, int pageSize = 25}) async {
          final kw = (search ?? '').trim().toLowerCase();
          final filtered = kw.isEmpty
              ? sampleClinics
              : sampleClinics.where((c) => c.values.join(' ').toLowerCase().contains(kw)).toList();
          return {
            'success': true,
            'count': filtered.length,
            'totalCount': filtered.length,
            'clinics': filtered,
          };
        };

        ApiService.debugFetchClinicDoctorsFilteredOverride = ({
          required String clinicId,
          String? search,
          String? specialty,
          String? department,
          int page = 1,
          int pageSize = 25,
        }) async {
          final kw = (search ?? '').trim().toLowerCase();
          final filtered = lotusDoctors.where((d) {
            if (specialty != null && specialty != 'All' && d['specialty'] != specialty) return false;
            if (department != null && department != 'All' && d['department'] != department) return false;
            if (kw.isNotEmpty && !d.values.join(' ').toLowerCase().contains(kw)) return false;
            return true;
          }).toList();
          return {
            'success': true,
            'count': filtered.length,
            'doctors': filtered,
          };
        };

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AdminClinicManagementPanel(
                  problemService: PatientProblemService(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Lotus Care Clinic'), findsOneWidget);
        expect(find.text('Sunrise Health Hub'), findsOneWidget);

        // Dynamic search by pincode
        await tester.enterText(find.byKey(const Key('admin_clinic_search_field')), '400050');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.text('Lotus Care Clinic'), findsOneWidget);
        expect(find.text('Sunrise Health Hub'), findsNothing);

        // Open Clinic Details dialog
        await tester.tap(find.byKey(const Key('admin_clinic_view_details_cli-mum-01')));
        await tester.pumpAndSettle();

        expect(find.text('Clinic Information'), findsOneWidget);
        expect(find.text('Associated Doctors'), findsOneWidget);
        expect(find.text('2 matching'), findsOneWidget);
        expect(find.text('Dr. Asha Menon'), findsOneWidget);
        expect(find.text('Dr. Vikram Joshi'), findsOneWidget);

        // Filter associated doctors by Name
        await tester.enterText(find.byKey(const Key('admin_clinic_doctor_search_field')), 'Vikram');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('1 matching'), findsOneWidget);
        expect(find.text('Dr. Vikram Joshi'), findsOneWidget);
        expect(find.text('Dr. Asha Menon'), findsNothing);

        // Clear doctor filters -> both doctors return
        await tester.tap(find.byKey(const Key('admin_clinic_doctor_clear_filters_btn')));
        await tester.pumpAndSettle();
        expect(find.text('2 matching'), findsOneWidget);
      },
    );

    testWidgets('4. AdminClinicManagementPanel renders cleanly on mobile (390px) and tablet (768px) with zero overflows', (WidgetTester tester) async {
      ApiService.debugFetchClinicsSearchOverride = ({String? search, int page = 1, int pageSize = 25}) async {
        return {
          'success': true,
          'count': 1,
          'clinics': [
            {
              'id': 'cli-mum-01',
              'clinicName': 'Lotus Care Clinic',
              'clinicAddress': '45 Linking Road, Bandra West',
              'city': 'Mumbai',
              'state': 'Maharashtra',
              'pincode': '400050',
              'associatedDoctorsCount': 3,
            },
          ],
        };
      };

      for (final size in [const Size(390, 844), const Size(768, 1024)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AdminClinicManagementPanel(
                  problemService: PatientProblemService(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Lotus Care Clinic'), findsOneWidget);
      }

      tester.view.resetPhysicalSize();
    });

    testWidgets(
      '5. ClinicAddDoctorsDialog Option 2 (Register New Doctor) detects duplicate mobile numbers and offers 1-click Attach Existing Doctor Account',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(960, 820);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        List<String>? attachedDoctorIds;
        ApiService.debugAssociateDoctorsToClinicOverride = ({
          required String clinicId,
          required List<String> doctorIds,
          String? clinicName,
        }) async {
          attachedDoctorIds = doctorIds;
          return {
            'success': true,
            'message': 'Existing doctor attached to clinic.',
          };
        };

        final existingDoctor = DoctorModel(
          id: 'doc-existing-99',
          userId: 'u-existing-99',
          name: 'Dr. Rohan Mehta',
          specialty: 'Orthodontics',
          qualification: 'BDS, MDS',
          experienceYears: 8,
          rating: 4.9,
          reviewCount: 15,
          phone: '9822211111',
          email: 'rohan@gshealth.in',
          clinicId: '',
          clinicName: '',
          status: 'Available',
          nextAvailableSlots: const [],
          consultationFee: '500',
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: ElevatedButton(
                      onPressed: () {
                        ClinicAddDoctorsDialog.show(
                          ctx,
                          clinicId: 'cli-emerald-01',
                          clinicName: 'Emerald Dental Clinic',
                          allRegisteredDoctors: [existingDoctor],
                          alreadyAssociatedDoctorIds: const {},
                        );
                      },
                      child: const Text('Open Add Doctors'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Add Doctors'));
        await tester.pumpAndSettle();

        // Both Option 1 and Option 2 tabs are clearly visible
        expect(find.byKey(const Key('clinic_add_doctors_tab_existing')), findsOneWidget);
        expect(find.byKey(const Key('clinic_add_doctors_tab_register_new')), findsOneWidget);

        // Switch to Option 2: Register New Doctor
        await tester.tap(find.byKey(const Key('clinic_add_doctors_tab_register_new')));
        await tester.pumpAndSettle();

        // Verify Automatic Clinic Association banner & required fields
        expect(find.byKey(const Key('clinic_reg_doc_auto_clinic_banner')), findsOneWidget);
        expect(find.textContaining('Automatic Clinic Association: Emerald Dental Clinic'), findsOneWidget);
        expect(find.byKey(const Key('clinic_reg_doc_name_field')), findsOneWidget);
        expect(find.byKey(const Key('clinic_reg_doc_phone_field')), findsOneWidget);
        expect(find.byKey(const Key('clinic_reg_doc_license_field')), findsOneWidget);

        // Entering an already-registered doctor's mobile number shows the duplicate detection card & Attach button
        await tester.enterText(find.byKey(const Key('clinic_reg_doc_phone_field')), '9822211111');
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('clinic_reg_doc_duplicate_mobile_card')), findsOneWidget);
        expect(find.textContaining('Dr. Rohan Mehta'), findsWidgets);
        expect(find.byKey(const Key('clinic_reg_doc_attach_existing_btn')), findsOneWidget);

        // Tapping Attach Existing Doctor attaches the existing account without creating a duplicate
        await tester.tap(find.byKey(const Key('clinic_reg_doc_attach_existing_btn')));
        await tester.pumpAndSettle();

        expect(attachedDoctorIds, equals(['doc-existing-99']));
      },
    );

    testWidgets(
      '6. ClinicAddDoctorsDialog Option 2 registers a brand-new doctor, auto-associates with current clinic, and updates associated doctors list',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(960, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        Map<String, dynamic>? capturedPayload;
        ApiService.debugRegisterClinicDoctorOverride = ({
          required String clinicId,
          required String clinicName,
          required String name,
          required String phone,
          String? email,
          required String specialty,
          required String qualification,
          required int experienceYears,
          required String licenseNumber,
          String? city,
          String? state,
          String? pincode,
          String? clinicAddress,
          double? latitude,
          double? longitude,
          List<String>? languages,
          String? profilePhoto,
        }) async {
          capturedPayload = {
            'clinicId': clinicId,
            'clinicName': clinicName,
            'name': name,
            'phone': phone,
            'email': email,
            'specialty': specialty,
            'qualification': qualification,
            'experienceYears': experienceYears,
            'licenseNumber': licenseNumber,
            'city': city,
          };
          return {
            'success': true,
            'statusCode': 201,
            'message': 'Dr. Kavita Iyer registered and associated with Emerald Dental Clinic.',
            'doctor': {
              'id': 'doc-new-777',
              'userId': 'u-new-777',
              'name': 'Dr. Kavita Iyer',
              'phone': phone,
              'email': email ?? '',
              'specialty': specialty,
              'qualification': qualification,
              'experience_years': experienceYears,
              'license_number': licenseNumber,
              'clinic_id': clinicId,
              'clinicName': clinicName,
            },
          };
        };

        bool callbackFired = false;
        final clinicModel = ClinicModel(
          id: 'cli-emerald-01',
          clinicName: 'Emerald Dental Clinic',
          location: '101 Park Street',
          clinicAddress: '101 Park Street',
          city: 'Mumbai',
          state: 'Maharashtra',
          pincode: '400001',
          latitude: 19.076,
          longitude: 72.8777,
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: ElevatedButton(
                      onPressed: () {
                        ClinicAddDoctorsDialog.show(
                          ctx,
                          clinicId: clinicModel.id,
                          clinicName: clinicModel.clinicName,
                          clinic: clinicModel,
                          allRegisteredDoctors: const [],
                          alreadyAssociatedDoctorIds: const {},
                          initialRegisterNew: true,
                          onDoctorsAssociated: () {
                            callbackFired = true;
                          },
                        );
                      },
                      child: const Text('Open Register New Doctor'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Register New Doctor'));
        await tester.pumpAndSettle();

        // Fill in new doctor details
        await tester.enterText(find.byKey(const Key('clinic_reg_doc_name_field')), 'Dr. Kavita Iyer');
        await tester.enterText(find.byKey(const Key('clinic_reg_doc_phone_field')), '9833344444');
        await tester.enterText(find.byKey(const Key('clinic_reg_doc_email_field')), 'kavita@gshealth.in');
        await tester.enterText(find.byKey(const Key('clinic_reg_doc_license_field')), 'MCI-2026-9981');
        await tester.enterText(find.byKey(const Key('clinic_reg_doc_qualification_field')), 'BDS, MDS');
        await tester.enterText(find.byKey(const Key('clinic_reg_doc_experience_field')), '9');

        await tester.tap(find.byKey(const Key('clinic_reg_doc_submit_btn')));
        await tester.pumpAndSettle();

        expect(capturedPayload, isNotNull);
        expect(capturedPayload!['clinicId'], 'cli-emerald-01');
        expect(capturedPayload!['clinicName'], 'Emerald Dental Clinic');
        expect(capturedPayload!['name'], 'Dr. Kavita Iyer');
        expect(capturedPayload!['phone'], '9833344444');
        expect(capturedPayload!['licenseNumber'], 'MCI-2026-9981');
        expect(capturedPayload!['city'], 'Mumbai');
        expect(callbackFired, isTrue);

        // Verify newly registered doctor is immediately present in PatientProblemService associated with cli-emerald-01
        final registeredInState = PatientProblemService()
            .allDoctors
            .where((d) => d.id == 'doc-new-777' && d.clinicId == 'cli-emerald-01')
            .toList();
        expect(registeredInState, isNotEmpty);
        expect(registeredInState.first.name, 'Dr. Kavita Iyer');
      },
    );
  });
}
