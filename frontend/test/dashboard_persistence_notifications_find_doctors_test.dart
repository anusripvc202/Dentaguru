import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String patientId = '58df98d2-b368-48a2-bd78-21dab59bca86';
  const String docUserId = '0c28684d-aa8b-4fe3-a7a5-1caeafcf0420';
  const String docDentistId = 'f4590a9d-75a3-4368-bd11-f00adcc1bcfd';
  const String apptId = '2349f963-fe9e-4b16-8553-a538b8d16c0a';

  late List<Map<String, dynamic>> mockAppointments;
  late List<Map<String, dynamic>> mockNotifications;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final todayIso = DateTime.now().toIso8601String().split('T').first;

    mockAppointments = [
      {
        'id': apptId,
        'patient_id': patientId,
        'dentist_id': docDentistId,
        'clinic_id': 'c1111111-1111-1111-1111-111111111111',
        'date': '${todayIso}T00:00:00.000Z',
        'time_slot': '09:30 AM',
        'treatment': 'Orthodontic Consultation',
        'status': 'PENDING',
        'created_at': '2026-11-18T10:30:00.000Z',
        'booking_created_at': '2026-11-18T10:30:00.000Z',
        'patient_name': 'Anu Sharma',
        'patient_phone': '9063663180',
        'patient_city': 'Hyderabad',
        'patient_pincode': '500081',
        'dentist_name': 'Dr. Sri Rao',
        'doctor_specialty': 'Orthodontics',
        'clinic_name': 'GS Health Ortho Clinic',
        'selectedDoctor': {
          'id': docDentistId,
          'user_id': docUserId,
          'name': 'Dr. Sri Rao',
          'specialty': 'Orthodontics',
          'qualification': 'BDS, MDS',
          'clinicId': 'c1111111-1111-1111-1111-111111111111',
          'clinicName': 'GS Health Ortho Clinic',
        },
        'patient': {
          'id': patientId,
          'name': 'Anu Sharma',
          'phone': '9063663180',
          'city': 'Hyderabad',
          'pincode': '500081',
          'age': '28',
          'gender': 'Female',
        },
        'clinic': {
          'id': 'c1111111-1111-1111-1111-111111111111',
          'clinic_name': 'GS Health Ortho Clinic',
          'location': 'Jubilee Hills, Hyderabad',
        },
      },
    ];

    mockNotifications = [
      {
        'id': 'notif-pat-1',
        'recipient_role': 'Patient',
        'recipient_id': patientId,
        'title': '✅ Appointment Booking Submitted',
        'message': 'Your appointment with Dr. Sri Rao (GS Health Ortho Clinic) at 09:30 AM has been booked.',
        'read': false,
        'created_at': '2026-11-18T10:30:05.000Z',
      },
      {
        'id': 'notif-doc-1',
        'recipient_role': 'Dentist',
        'recipient_id': docDentistId,
        'title': '📅 New Appointment Booked',
        'message': 'Anu Sharma booked an appointment for Orthodontic Consultation at 09:30 AM.',
        'read': false,
        'created_at': '2026-11-18T10:30:05.000Z',
      },
      {
        'id': 'notif-adm-1',
        'recipient_role': 'Admin',
        'recipient_id': 'ALL_ADMINS',
        'title': '📋 New Appointment Booked',
        'message': 'Anu Sharma booked an appointment with Dr. Sri Rao at 09:30 AM.',
        'read': false,
        'created_at': '2026-11-18T10:30:05.000Z',
      },
    ];

    ApiService.debugFetchAppointmentsOverride = ({String? patientId, String? dentistId}) async {
      return mockAppointments;
    };
    ApiService.debugAdminAppointmentsOverride = () async {
      return mockAppointments;
    };
    ApiService.debugFetchNotificationsOverride = ({String? role, String? userId}) async {
      final r = (role ?? '').toLowerCase();
      if (r.contains('admin')) {
        return mockNotifications.where((n) => n['recipient_role'] == 'Admin').toList();
      }
      if (r.contains('dentist') || r.contains('doctor')) {
        return mockNotifications.where((n) => n['recipient_role'] == 'Dentist').toList();
      }
      return mockNotifications.where((n) => n['recipient_role'] == 'Patient').toList();
    };
  });

  tearDown(() {
    ApiService.debugFetchAppointmentsOverride = null;
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchNotificationsOverride = null;
  });

  testWidgets('1. Patient Dashboard persists booked appointment & notifications after logout and re-login', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final service = PatientProblemService();
    await service.clearAllData();

    // Simulate Patient A logging back in after logout (local state cleared)
    service.updatePatientProfile(
      id: patientId,
      name: 'Anu Sharma',
      email: 'anu@gshealth.in',
      phone: '9063663180',
      age: '28',
      gender: 'Female',
      bloodGroup: 'O+',
      emergencyContact: '9063663180',
      city: 'Hyderabad',
      pincode: '500081',
    );
    service.addTestDoctor(
      DoctorModel(
        id: docDentistId,
        userId: docUserId,
        name: 'Dr. Sri Rao',
        specialty: 'Orthodontics',
        qualification: 'BDS, MDS',
        experienceYears: 8,
        rating: 4.9,
        reviewCount: 15,
        clinicName: 'GS Health Ortho Clinic',
        phone: '8985732916',
        email: 'sri@gshealth.in',
        status: 'Available',
        nextAvailableSlots: const ['09:30 AM'],
        consultationFee: '₹500',
        city: 'Hyderabad',
        pincode: '500081',
      ),
    );

    await service.syncAppointmentsFromApi();
    await service.syncNotificationsFromApi(role: 'Patient', userId: patientId);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PatientDashboardScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Verify unread notification badge is visible on Patient Dashboard
    expect(find.byKey(const Key('patient_unread_notifications_badge')), findsOneWidget);

    // Open Patient Notifications modal and verify notification details + mark all read
    await tester.tap(find.byKey(const Key('patient_notifications_bell_button')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Appointment Booking Submitted'), findsOneWidget);
    expect(find.byKey(const Key('patient_mark_all_notifications_read')), findsOneWidget);

    await tester.tap(find.byKey(const Key('patient_mark_all_notifications_read')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 300));

    // Switch to Visits tab (index 2) and verify all required booking details
    await tester.tap(find.text('Visits'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('visit_card_$apptId')), findsOneWidget);
    expect(find.text('Dr. Sri Rao'), findsWidgets);
    expect(find.text('Orthodontics'), findsWidgets);
    expect(find.text('GS Health Ortho Clinic'), findsWidgets);
    expect(find.textContaining('09:30 AM'), findsWidgets);
    expect(find.textContaining('Booked:'), findsOneWidget);
    expect(find.textContaining('ID: $apptId'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('2. Doctor Dashboard persists booked appointment & notifications after logout and re-login (even when logged in with users.id)', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final service = PatientProblemService();
    await service.clearAllData();

    // Simulate Doctor logging in where initial session has users.id (docUserId) and dentists table has docDentistId
    service.addTestDoctor(
      DoctorModel(
        id: docDentistId,
        userId: docUserId,
        name: 'Dr. Sri Rao',
        specialty: 'Orthodontics',
        qualification: 'BDS, MDS',
        experienceYears: 8,
        rating: 4.9,
        reviewCount: 15,
        clinicName: 'GS Health Ortho Clinic',
        phone: '8985732916',
        email: 'sri@gshealth.in',
        status: 'Available',
        nextAvailableSlots: const ['09:30 AM'],
        consultationFee: '₹500',
        city: 'Hyderabad',
        pincode: '500081',
      ),
    );
    service.currentDoctor = service.allDoctors.first;
    service.setDentistMode(true);

    await service.syncAppointmentsFromApi();
    await service.syncNotificationsFromApi(role: 'Dentist', userId: docUserId);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: DentistTimelineScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Verify appointment card is visible on Doctor Dashboard Today tab with patient details, clinic, status, and booking time
    expect(find.byKey(const Key('doctor_appointment_card_$apptId')), findsOneWidget);
    expect(find.text('Anu Sharma'), findsWidgets);
    expect(find.textContaining('Patient: Anu Sharma'), findsOneWidget);
    expect(find.textContaining('9063663180'), findsWidgets);
    expect(find.textContaining('Hyderabad (500081)'), findsOneWidget);
    expect(find.textContaining('09:30 AM'), findsWidgets);
    expect(find.textContaining('Clinic: GS Health Ortho Clinic'), findsOneWidget);
    expect(find.textContaining('Booked:'), findsOneWidget);
    expect(find.byKey(const Key('doctor_view_patient_details_btn_$apptId')), findsOneWidget);

    // Verify Accept Appointment & Decline buttons are visible on Pending appointment card
    final acceptBtn = find.byKey(const Key('doctor_accept_appointment_btn_$apptId'));
    final rejectBtn = find.byKey(const Key('doctor_reject_appointment_btn_$apptId'));
    expect(acceptBtn, findsOneWidget);
    expect(rejectBtn, findsOneWidget);

    // When doctor taps Accept Appointment, mock backend transitions status to CONFIRMED
    mockAppointments[0]['status'] = 'CONFIRMED';
    await tester.ensureVisible(acceptBtn);
    await tester.tap(acceptBtn);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('doctor_accepted_badge_$apptId')), findsOneWidget);
    expect(find.text('Appointment Accepted & Confirmed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('3. Admin Dashboard displays exact selected doctor, booking details & persistent Admin notifications', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final service = PatientProblemService();
    await service.clearAllData();
    service.setAdminMode(true);
    await service.syncNotificationsFromApi(role: 'Admin');

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AdminDashboardScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Anu Sharma'), findsWidgets);
    expect(find.text('Dr. Sri Rao'), findsWidgets);
    expect(find.textContaining('Orthodontics'), findsWidgets);
    expect(find.textContaining('GS Health Ortho Clinic'), findsWidgets);
    expect(find.byKey(const Key('admin_desktop_unread_notifications_badge')), findsOneWidget);

    // Open Admin Notifications modal and mark all read
    await tester.tap(find.byKey(const Key('admin_desktop_notifications_button')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('New Appointment Booked'), findsOneWidget);
    expect(find.byKey(const Key('admin_mark_all_notifications_read')), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin_mark_all_notifications_read')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('4. Find Doctors displays all available ON doctors with full details, hides OFF doctors, and supports pagination', (tester) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final service = PatientProblemService();
    await service.clearAllData();

    // Add 22 ON doctors + 1 OFF doctor to verify both ON/OFF filtering and pagination (page size 20)
    for (int i = 1; i <= 22; i++) {
      service.addTestDoctor(
        DoctorModel(
          id: 'doc-on-$i',
          userId: 'user-on-$i',
          name: 'Dr. Active Specialist $i',
          specialty: i.isEven ? 'Orthodontics' : 'General Dentistry',
          qualification: 'BDS, MDS',
          experienceYears: 6,
          rating: 4.8,
          reviewCount: 10,
          clinicName: 'GS Care Clinic $i',
          phone: '90000000${i.toString().padLeft(2, '0')}',
          email: 'doc$i@gshealth.in',
          status: 'Available',
          nextAvailableSlots: const ['10:00 AM'],
          consultationFee: '₹500',
          city: 'Hyderabad',
          pincode: '500081',
        ),
      );
    }
    service.addTestDoctor(
      DoctorModel(
        id: 'doc-off-99',
        userId: 'user-off-99',
        name: 'Dr. Hidden Offline Doctor',
        specialty: 'Endodontics',
        qualification: 'BDS, MDS',
        experienceYears: 10,
        rating: 4.9,
        reviewCount: 20,
        clinicName: 'Offline Clinic',
        phone: '9000000099',
        email: 'offline@gshealth.in',
        status: 'Unavailable',
        nextAvailableSlots: const [],
        consultationFee: '₹600',
        city: 'Hyderabad',
        pincode: '500081',
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: FindDoctorsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // Verify ON doctors are shown with specialization, qualifications, clinic, and Available badge
    expect(find.text('Dr. Active Specialist 1'), findsOneWidget);
    expect(find.text('General Dentistry • BDS, MDS'), findsWidgets);
    expect(find.text('GS Care Clinic 1 • Hyderabad'), findsOneWidget);
    expect(find.byKey(const Key('doctor_availability_badge_doc-on-1')), findsOneWidget);

    // Verify OFF doctor is excluded from patient Find Doctors
    expect(find.text('Dr. Hidden Offline Doctor'), findsNothing);

    // Verify pagination Load More button is shown for 22 available doctors (20 shown initially, 2 remaining)
    final loadMoreFinder = find.byKey(const Key('find_doctors_load_more_button'));
    expect(loadMoreFinder, findsOneWidget);
    expect(find.text('Dr. Active Specialist 22'), findsNothing);

    await tester.ensureVisible(loadMoreFinder);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(loadMoreFinder);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Dr. Active Specialist 22'), findsOneWidget);
  });
}
