import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/constants/patient_profile_requirements.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/theme/app_theme.dart';
import 'package:dentaguru/features/auth/presentation/screens/auth_screen.dart';
import 'package:dentaguru/features/dentist/presentation/screens/doctor_profile_screen.dart' as dentist_profile;
import 'package:dentaguru/features/patient/presentation/screens/doctor_profile_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_profile_completion_screen.dart';

final Uint8List _testPngBytes = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PatientProfileRequirementsConfig.resetDefaults();
    ApiService.debugRegisterOverride = null;
    ApiService.debugUpdatePatientProfileOverride = null;
    ApiService.debugFetchDentistsOverride = null;
    ApiService.debugFetchDoctorLanguagesOverride = null;
    ApiService.debugUpdateDoctorProfileOverride = null;
    AuthScreen.debugPickRegistrationImageOverride = null;
    dentist_profile.DoctorProfileScreen.debugPickProfileImageOverride = null;
    PatientProfileCompletionScreen.debugPickImageOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    ApiService.debugRegisterOverride = null;
    ApiService.debugUpdatePatientProfileOverride = null;
    ApiService.debugFetchDentistsOverride = null;
    ApiService.debugFetchDoctorLanguagesOverride = null;
    ApiService.debugUpdateDoctorProfileOverride = null;
    AuthScreen.debugPickRegistrationImageOverride = null;
    dentist_profile.DoctorProfileScreen.debugPickProfileImageOverride = null;
    PatientProfileCompletionScreen.debugPickImageOverride = null;
    PatientProfileRequirementsConfig.resetDefaults();
    await SessionService().clearSession();
  });

  group('Patient Optional Fields & Doctor Registration Profile Image', () {
    testWidgets('1. Patient profile completion succeeds without image, pincode, or age and shows no required asterisks for them', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      expect(PatientProfileRequirementsConfig.requireProfileImage, isFalse);
      expect(PatientProfileRequirementsConfig.requirePincode, isFalse);
      expect(PatientProfileRequirementsConfig.requireAge, isFalse);
      expect(PatientProfileRequirementsConfig.requireGender, isTrue);

      await SessionService().saveSession(
        token: 'pat-jwt-opt-1',
        role: 'Patient',
        userId: 'pat-opt-1',
        phone: '9123456101',
        name: 'Patient',
      );
      PatientProblemService().currentPatient = PatientProfile(
        id: 'pat-opt-1',
        name: 'Patient',
        phone: '9123456101',
        age: '',
        gender: '',
        pincode: '',
      );

      String? sentPincode;
      String? sentAge;
      String? sentGender;
      String? sentPhoto;
      bool completed = false;

      ApiService.debugUpdatePatientProfileOverride = ({
        required String patientId,
        String? pincode,
        String? age,
        String? gender,
        String? profilePhoto,
        String? name,
        String? city,
        bool completeProfile = true,
      }) async {
        sentPincode = pincode;
        sentAge = age;
        sentGender = gender;
        sentPhoto = profilePhoto;
        return {
          'success': true,
          'user': {
            'id': patientId,
            'name': name ?? 'Patient',
            'pincode': pincode ?? '',
            'age': age ?? '',
            'gender': gender ?? '',
            'profilePhoto': profilePhoto,
            'isProfileComplete': true,
          },
        };
      };

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: PatientProfileCompletionScreen(
              serviceTitle: 'Find Doctors',
              onCompleted: () => completed = true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      // Verify labels show (OPTIONAL) and NO asterisks on Profile Image, Pincode, Age
      expect(find.text('PROFILE IMAGE (OPTIONAL)'), findsOneWidget);
      expect(find.text('PINCODE (OPTIONAL)'), findsOneWidget);
      expect(find.text('AGE (OPTIONAL)'), findsOneWidget);
      expect(find.text('PROFILE IMAGE *'), findsNothing);
      expect(find.text('PINCODE *'), findsNothing);
      expect(find.text('AGE *'), findsNothing);
      expect(find.text('GENDER *'), findsOneWidget);

      // Select ONLY Gender (leave image, pincode, and age blank)
      final genderMale = find.byKey(const Key('profile_completion_gender_Male'));
      await tester.ensureVisible(genderMale);
      await tester.tap(genderMale);
      await tester.pump();

      final submitBtn = find.byKey(const Key('profile_completion_submit_button'));
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(completed, isTrue);
      expect(sentGender, equals('Male'));
      expect(sentPincode, isEmpty);
      expect(sentAge, isEmpty);
      expect(sentPhoto, isNull);
    });

    testWidgets('2. Patient registration succeeds without image, age, and pincode, and also with all optional fields', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      Map<String, dynamic>? capturedPayload;
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
        String? location,
        String? state,
        String? city,
        String? pincode,
        double? latitude,
        double? longitude,
        String? qualification,
        int? experienceYears,
        String? consultationFee,
        String? bio,
        String? profilePhoto,
        List<String>? languages,
        String? referralCode,
      }) async {
        capturedPayload = {
          'name': name,
          'phone': phone,
          'role': role,
          'city': city,
          'age': age,
          'pincode': pincode,
          'profilePhoto': profilePhoto,
        };
        return {
          'success': true,
          'data': {
            'accessToken': 'pat-reg-jwt',
            'user': {
              'id': 'pat-new-101',
              'name': name,
              'phone': phone,
              'role': 'Patient',
              'city': city,
              'age': age ?? '',
              'pincode': pincode ?? '',
              'profilePhoto': profilePhoto,
            },
          },
        };
      };

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(
              initialTab: 0,
              initialRole: 'Patient',
              initialVerifiedPhone: '9876543101',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      await tester.enterText(find.byKey(const Key('reg_full_name_field')), 'Riya Sharma');
      await tester.enterText(find.byKey(const Key('reg_city_field')), 'Hyderabad');
      final continueBtn = find.byKey(const Key('reg_continue_button'));
      await tester.ensureVisible(continueBtn);
      await tester.tap(continueBtn);
      await tester.pump(const Duration(milliseconds: 250));

      expect(capturedPayload, isNotNull);
      expect(capturedPayload!['name'], equals('Riya Sharma'));
      expect(capturedPayload!['role'], equals('Patient'));
      expect(capturedPayload!['age'], equals(''));
      expect(capturedPayload!['pincode'], equals(''));
      expect(capturedPayload!['profilePhoto'], isNull);
    });

    testWidgets('3, 4 & 5. Doctor Registration supports optional photo preview, change, remove, upload error handling, and submission with/without image', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      ImageSource? lastPickerSource;
      int pickSeq = 0;
      AuthScreen.debugPickRegistrationImageOverride = (ImageSource source) async {
        lastPickerSource = source;
        pickSeq++;
        return (bytes: _testPngBytes, name: 'doctor_avatar_$pickSeq.png');
      };

      String? capturedPhotoDataUri;
      bool simulateUploadFailure = true;
      const uploadedStorageUrl =
          'https://ojinzcdldwugpnxrnjcq.supabase.co/storage/v1/object/public/dentaguru-storage/avatars/doctors/doc_1.png';

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
        String? location,
        String? state,
        String? city,
        String? pincode,
        double? latitude,
        double? longitude,
        String? qualification,
        int? experienceYears,
        String? consultationFee,
        String? bio,
        String? profilePhoto,
        List<String>? languages,
        String? referralCode,
      }) async {
        capturedPhotoDataUri = profilePhoto;
        if (simulateUploadFailure) {
          return {
            'success': false,
            'code': 'PROFILE_IMAGE_UPLOAD_FAILED',
            'message': 'Failed to upload profile image to storage. Please try again or remove the image.',
          };
        }
        return {
          'success': true,
          'data': {
            'accessToken': 'doc-reg-jwt',
            'user': {
              'id': 'doc-usr-501',
              'userId': 'doc-usr-501',
              'dentistId': 'doc-rec-501',
              'name': name,
              'phone': phone,
              'role': 'DOCTOR',
              'specialty': specialty ?? 'Cardiology',
              'qualification': qualification ?? 'MBBS, MD',
              'city': city ?? 'Hyderabad',
              'profilePhoto': profilePhoto != null ? uploadedStorageUrl : null,
            },
          },
        };
      };

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(
              initialTab: 0,
              initialRole: 'Dentist',
              initialVerifiedPhone: '9876543202',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      // Doctor profile photo section is visible and marked OPTIONAL
      expect(find.byKey(const Key('reg_doctor_photo_section')), findsOneWidget);
      expect(find.text('PROFILE IMAGE (OPTIONAL)'), findsOneWidget);
      expect(find.byKey(const Key('reg_doctor_pick_gallery_button')), findsOneWidget);
      expect(find.byKey(const Key('reg_doctor_pick_camera_button')), findsOneWidget);
      expect(find.byKey(const Key('reg_doctor_remove_photo_button')), findsNothing);

      // Pick image from Gallery -> preview & Remove button appear
      await tester.tap(find.byKey(const Key('reg_doctor_pick_gallery_button')));
      await tester.pump();
      expect(lastPickerSource, equals(ImageSource.gallery));
      expect(find.text('Profile photo selected'), findsOneWidget);
      expect(find.text('doctor_avatar_1.png'), findsOneWidget);
      expect(find.byKey(const Key('reg_doctor_remove_photo_button')), findsOneWidget);

      // Change photo via Camera -> updates preview filename
      await tester.tap(find.byKey(const Key('reg_doctor_pick_camera_button')));
      await tester.pump();
      expect(lastPickerSource, equals(ImageSource.camera));
      expect(find.text('doctor_avatar_2.png'), findsOneWidget);

      // Remove photo -> clears preview
      await tester.tap(find.byKey(const Key('reg_doctor_remove_photo_button')));
      await tester.pump();
      expect(find.text('Upload your profile photo'), findsOneWidget);
      expect(find.byKey(const Key('reg_doctor_remove_photo_button')), findsNothing);

      // Re-pick image, fill fields, and verify upload failure shows clear inline error
      await tester.tap(find.byKey(const Key('reg_doctor_pick_gallery_button')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('reg_full_name_field')), 'Dr. Meera Nair');
      await tester.enterText(find.byKey(const Key('reg_city_field')), 'Hyderabad');

      final continueBtn = find.byKey(const Key('reg_continue_button'));
      await tester.ensureVisible(continueBtn);
      await tester.tap(continueBtn);
      await tester.pump(const Duration(milliseconds: 250));

      expect(capturedPhotoDataUri, equals('data:image/png;base64,${base64Encode(_testPngBytes)}'));
      expect(find.byKey(const Key('reg_doctor_photo_error')), findsOneWidget);

      // Retry with successful storage upload -> persists uploaded Storage URL in DoctorModel
      simulateUploadFailure = false;
      await tester.ensureVisible(continueBtn);
      await tester.tap(continueBtn);
      await tester.pump(const Duration(milliseconds: 250));

      final savedDoc = PatientProblemService().currentDoctor;
      expect(savedDoc, isNotNull);
      expect(savedDoc!.profileImageUrl, equals(uploadedStorageUrl));
      expect(savedDoc.hasProfileImage, isTrue);

      // Also verify doctor registration succeeds WITHOUT an image (optional)
      await SessionService().clearSession();
      await PatientProblemService().clearAllData();
      capturedPhotoDataUri = 'SENTINEL';

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            key: ValueKey('doc_reg_no_photo'),
            home: AuthScreen(
              initialTab: 0,
              initialRole: 'Dentist',
              initialVerifiedPhone: '9876543203',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      await tester.enterText(find.byKey(const Key('reg_full_name_field')), 'Dr. Arjun Verma');
      await tester.enterText(find.byKey(const Key('reg_city_field')), 'Bengaluru');
      final continueBtn2 = find.byKey(const Key('reg_continue_button'));
      await tester.ensureVisible(continueBtn2);
      await tester.tap(continueBtn2);
      await tester.pump(const Duration(milliseconds: 250));

      expect(capturedPhotoDataUri, isNull);
      expect(PatientProblemService().currentDoctor?.name, contains('Arjun Verma'));
    });

    testWidgets('6. Doctor uploaded image URL & memory bytes render in FindDoctorsScreen and DoctorProfileScreen', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const storageUrl =
          'https://ojinzcdldwugpnxrnjcq.supabase.co/storage/v1/object/public/dentaguru-storage/avatars/doctors/doc_url.png';

      ApiService.debugFetchDentistsOverride = ({
        String? state,
        String? city,
        String? pincode,
        String? specialty,
        String? availability,
        String? language,
        List<String>? languages,
        String? search,
        bool includeUnavailable = false,
      }) async => [
        {
          'id': 'doc-url-1',
          'user_id': 'usr-url-1',
          'name': 'Dr. Priya Rao',
          'speciality': 'Cardiology',
          'qualifications': 'MBBS, MD',
          'experience_years': 8,
          'city': 'Hyderabad',
          'languages': ['English', 'Telugu'],
          'availability_status': 'Available',
          'onlineStatus': 'Online',
          'profilePhoto': storageUrl,
        },
        {
          'id': 'doc-mem-2',
          'user_id': 'usr-mem-2',
          'name': 'Dr. Kiran Kumar',
          'speciality': 'Dentistry',
          'qualifications': 'BDS, MDS',
          'experience_years': 6,
          'city': 'Hyderabad',
          'languages': ['English'],
          'availability_status': 'Available',
          'onlineStatus': 'Online',
          'profilePhoto': 'data:image/png;base64,${base64Encode(_testPngBytes)}',
        },
      ];
      ApiService.debugFetchDoctorLanguagesOverride = ({bool includeUnavailable = false}) async => ['English', 'Telugu'];

      await PatientProblemService().syncDoctorsFromApi(includeUnavailable: true);
      final synced = PatientProblemService().allDoctors;
      expect(synced.length, equals(2));
      expect(synced[0].profileImageUrl, equals(storageUrl));
      expect(synced[1].photoBytes, isNotNull);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: FindDoctorsScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(const Key('doctor_avatar_network_doc-url-1')), findsOneWidget);
      expect(find.byKey(const Key('doctor_avatar_memory_doc-mem-2')), findsOneWidget);

      // Also verify DoctorProfileScreen renders the uploaded network URL image
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DoctorProfileScreen(doctor: synced[0]),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('doctor_profile_avatar_network_doc-url-1')), findsOneWidget);
    });

    testWidgets('7. Doctor Edit Profile supports photo upload (Gallery/Camera), preview, upload error handling, save URL, and photo removal', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        ApiService.debugUpdateDoctorProfileOverride = null;
        dentist_profile.DoctorProfileScreen.debugPickProfileImageOverride = null;
      });

      final service = PatientProblemService();
      service.registerDoctor(
        id: 'doc-edit-1',
        userId: 'usr-edit-1',
        name: 'Dr. Rohan Mehta',
        specialty: 'Cardiology',
        qualification: 'MBBS, MD',
        experienceYears: 9,
        clinicName: 'Heart Care Clinic',
        phone: '9876543299',
        email: 'rohan@gshealth.in',
        licenseNumber: 'MED-CARD-99',
      );

      ImageSource? lastSource;
      dentist_profile.DoctorProfileScreen.debugPickProfileImageOverride = (ImageSource src) async {
        lastSource = src;
        return (bytes: _testPngBytes, name: 'rohan_avatar.png');
      };

      const uploadedUrl =
          'https://ojinzcdldwugpnxrnjcq.supabase.co/storage/v1/object/public/dentaguru-storage/avatars/doctors/rohan_avatar.png';
      bool simulateFailure = true;
      Map<String, dynamic>? lastPayload;

      ApiService.debugUpdateDoctorProfileOverride = (String doctorId, Map<String, dynamic> updates) async {
        lastPayload = Map<String, dynamic>.from(updates);
        if (simulateFailure) {
          return {
            'success': false,
            'code': 'PROFILE_IMAGE_UPLOAD_FAILED',
            'message': 'Failed to upload profile image to storage.',
          };
        }
        return {
          'success': true,
          'doctor': {
            'id': doctorId,
            'profilePhoto': updates['removeProfilePhoto'] == true ? null : uploadedUrl,
          },
        };
      };

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: dentist_profile.DoctorProfileScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      // Open Edit Doctor Profile sheet
      await tester.tap(find.byKey(const Key('doctor_profile_edit_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('edit_doctor_photo_section')), findsOneWidget);
      expect(find.byKey(const Key('edit_doctor_pick_gallery_button')), findsOneWidget);
      expect(find.byKey(const Key('edit_doctor_pick_camera_button')), findsOneWidget);

      // Pick image from Gallery -> preview & Remove appear
      await tester.tap(find.byKey(const Key('edit_doctor_pick_gallery_button')));
      await tester.pump();
      expect(lastSource, equals(ImageSource.gallery));
      expect(find.byKey(const Key('edit_doctor_photo_preview_memory')), findsOneWidget);
      expect(find.byKey(const Key('edit_doctor_remove_photo_button')), findsOneWidget);

      // Simulate storage upload failure -> stays open and shows inline error
      final saveBtn = find.byKey(const Key('save_doctor_profile_button'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump(const Duration(milliseconds: 250));

      expect(lastPayload?['profilePhoto'], equals('data:image/png;base64,${base64Encode(_testPngBytes)}'));
      expect(find.byKey(const Key('edit_doctor_photo_error')), findsOneWidget);

      // Retry with successful upload -> closes sheet, saves Storage URL & renders avatar
      simulateFailure = false;
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.currentDoctor?.profileImageUrl, equals(uploadedUrl));
      expect(find.byKey(const Key('doctor_own_profile_avatar_memory')), findsOneWidget);

      // Re-open Edit Profile and remove photo -> sends removeProfilePhoto: true & clears image
      await tester.tap(find.byKey(const Key('doctor_profile_edit_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('edit_doctor_remove_photo_button')));
      await tester.pump();

      final saveBtn2 = find.byKey(const Key('save_doctor_profile_button'));
      await tester.ensureVisible(saveBtn2);
      await tester.tap(saveBtn2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(lastPayload?['removeProfilePhoto'], isTrue);
      expect(service.currentDoctor?.profileImageUrl, isNull);
      expect(service.currentDoctor?.photoBytes, isNull);
    });
  });
}
