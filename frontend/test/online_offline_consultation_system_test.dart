import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';
import 'package:dentaguru/features/patient/presentation/widgets/book_visit_flow_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final onlineOnlyDoctor = DoctorModel(
    id: 'doc-online-1',
    userId: 'u-online-1',
    name: 'Dr. Kavita TeleMed',
    specialty: 'Dermatology',
    qualification: 'MBBS, MD (Dermatology)',
    experienceYears: 9,
    rating: 4.9,
    reviewCount: 34,
    clinicName: 'GS TeleHealth Hub',
    clinicAddress: 'Cyber Towers, Hitech City',
    city: 'Hyderabad',
    state: 'Telangana',
    pincode: '500081',
    phone: '9876500001',
    email: 'kavita@dentaguru.com',
    status: 'Available',
    onlineStatus: 'Online',
    nextAvailableSlots: const ['10:00 AM', '11:30 AM'],
    consultationFee: '₹500',
    onlineConsultationEnabled: true,
    inPersonConsultationEnabled: false,
  );

  final offlineOnlyDoctor = DoctorModel(
    id: 'doc-offline-1',
    userId: 'u-offline-1',
    name: 'Dr. Rajesh OrthoClinic',
    specialty: 'Orthopedics',
    qualification: 'MBBS, MS (Ortho)',
    experienceYears: 14,
    rating: 4.8,
    reviewCount: 52,
    clinicName: 'Apollo Ortho Care Clinic',
    clinicAddress: 'Plot 42, Road No 12, Banjara Hills',
    city: 'Hyderabad',
    state: 'Telangana',
    pincode: '500034',
    latitude: 17.4156,
    longitude: 78.4347,
    phone: '9876500002',
    email: 'rajesh@dentaguru.com',
    status: 'Available',
    nextAvailableSlots: const ['09:30 AM', '04:00 PM'],
    consultationFee: '₹700',
    onlineConsultationEnabled: false,
    inPersonConsultationEnabled: true,
  );

  final bothModesDoctor = DoctorModel(
    id: 'doc-both-1',
    userId: 'u-both-1',
    name: 'Dr. Meera HybridCare',
    specialty: 'Cardiology',
    qualification: 'MBBS, MD, DM (Cardiology)',
    experienceYears: 16,
    rating: 5.0,
    reviewCount: 88,
    clinicName: 'Star Heart Institute',
    clinicAddress: 'Jubilee Hills Checkpost',
    city: 'Hyderabad',
    state: 'Telangana',
    pincode: '500033',
    latitude: 17.4254,
    longitude: 78.4148,
    phone: '9876500003',
    email: 'meera@dentaguru.com',
    status: 'Available',
    onlineStatus: 'Online',
    nextAvailableSlots: const ['10:00 AM', '02:00 PM'],
    consultationFee: '₹900',
    onlineConsultationEnabled: true,
    inPersonConsultationEnabled: true,
  );

  final unknownModesDoctor = DoctorModel.fromJson({
    'id': 'doc-unknown-1',
    'user_id': 'u-unknown-1',
    'name': 'Dr. Vikram Legacy',
    'specialty': 'General Medicine',
    'qualification': 'MBBS, MD',
    'experience_years': 7,
    'clinicName': 'Legacy Care Clinic',
    'clinicAddress': 'MG Road, Secunderabad',
    'city': 'Secunderabad',
    'state': 'Telangana',
    'pincode': '500003',
    'availability_status': 'Available',
    'consultation_fee': '₹400',
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final service = PatientProblemService();
    await service.clearAllData();
    service.addTestDoctor(onlineOnlyDoctor);
    service.addTestDoctor(offlineOnlyDoctor);
    service.addTestDoctor(bothModesDoctor);
    service.addTestDoctor(unknownModesDoctor);
  });

  group('Online and Offline Consultation Selection & Doctor Filtering System', () {
    test('Unknown consultation availability doctors are NOT marked as online-enabled by default', () {
      expect(unknownModesDoctor.onlineConsultationEnabled, isFalse);
      expect(unknownModesDoctor.inPersonConsultationEnabled, isTrue);
      expect(unknownModesDoctor.supportsOnlineConsultation, isFalse);
      expect(unknownModesDoctor.supportsInPersonConsultation, isTrue);
    });

    testWidgets(
      'Online Consultation mode shows ONLY online-enabled doctors with Online Consultation Available badge & Book Online button',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: FindDoctorsScreen(
                initialConsultationMode: 'Online',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Online-only and Both-mode doctors MUST be shown
        expect(find.text('Dr. Kavita TeleMed'), findsOneWidget);
        expect(find.text('Dr. Meera HybridCare'), findsOneWidget);

        // Offline-only and Unknown-mode doctors MUST NOT be shown
        expect(find.text('Dr. Rajesh OrthoClinic'), findsNothing);
        expect(find.text('Dr. Vikram Legacy'), findsNothing);

        // Online Consultation Available label & Book Online buttons are shown
        expect(
          find.byKey(const Key('doctor_online_consultation_badge_doc-online-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('doctor_online_consultation_badge_doc-both-1')),
          findsOneWidget,
        );
        expect(find.text('Online Consultation Available'), findsNWidgets(2));
        expect(
          find.byKey(const Key('doctor_book_online_btn_doc-online-1')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Offline Consultation mode shows ONLY in-person doctors with Clinic Name, Address, Location, Get Directions & Book Clinic Appointment',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: FindDoctorsScreen(
                initialConsultationMode: 'Offline',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // In-Person and Both-mode doctors MUST be shown
        expect(find.text('Dr. Rajesh OrthoClinic'), findsOneWidget);
        expect(find.text('Dr. Meera HybridCare'), findsOneWidget);
        expect(find.text('Dr. Vikram Legacy'), findsOneWidget);

        // Online-Only doctor MUST NOT be shown in Offline results
        expect(find.text('Dr. Kavita TeleMed'), findsNothing);

        // Clinic name, address, location, Get Directions, and Book Clinic Appointment button
        expect(
          find.textContaining('Apollo Ortho Care Clinic • Hyderabad, Telangana, 500034'),
          findsOneWidget,
        );
        expect(
          find.text('Plot 42, Road No 12, Banjara Hills'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('doctor_card_directions_doc-offline-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('doctor_book_offline_btn_doc-offline-1')),
          findsOneWidget,
        );
        expect(find.text('Book Clinic Appointment'), findsWidgets);
      },
    );

    testWidgets(
      'Empty state when no online doctors match location displays exact required message',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Set only offline/unknown doctors in service
        final service = PatientProblemService();
        await service.clearAllData();
        service.addTestDoctor(offlineOnlyDoctor);
        service.addTestDoctor(unknownModesDoctor);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: FindDoctorsScreen(
                initialConsultationMode: 'Online',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'No doctors are currently available for online consultation in your selected location.',
          ),
          findsOneWidget,
        );
        expect(find.text('Dr. Rajesh OrthoClinic'), findsNothing);
        expect(find.text('Dr. Vikram Legacy'), findsNothing);
      },
    );

    testWidgets(
      'Switching between Online Consultation and Offline Consultation cards dynamically filters doctors and preserves search/slot filters',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: FindDoctorsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Online Consultation card
        await tester.tap(find.byKey(const Key('find_doctors_mode_online_card')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Kavita TeleMed'), findsOneWidget);
        expect(find.text('Dr. Rajesh OrthoClinic'), findsNothing);

        // Tap Offline Consultation card
        await tester.tap(find.byKey(const Key('find_doctors_mode_offline_card')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Rajesh OrthoClinic'), findsOneWidget);
        expect(find.text('Dr. Kavita TeleMed'), findsNothing);
      },
    );

    testWidgets(
      'BookVisitFlowDialog blocks unsupported consultation mode when switching an offline-only doctor to Online',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: BookVisitFlowDialog(
                  preselectedDoctor: offlineOnlyDoctor,
                  initialConsultationMode: 'In-Person',
                  enableAutoRefresh: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // In-Person is supported -> no unsupported warning
        expect(find.byKey(const Key('booking_unsupported_mode_warning')), findsNothing);

        // Switch to Online mode on an offline-only doctor -> displays validation warning
        await tester.tap(find.byKey(const Key('booking_mode_online')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('booking_unsupported_mode_warning')), findsOneWidget);
        expect(
          find.textContaining('This doctor does not offer Online consultations'),
          findsOneWidget,
        );
      },
    );
  });
}
