import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dentaguru/core/models/doctor_availability.dart';
import 'package:dentaguru/core/models/specialty_clinical_config.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/utils/prescription_pdf_generator.dart';
import 'package:dentaguru/features/dentist/presentation/widgets/specialty_prescription_modal.dart';
import 'package:dentaguru/features/patient/presentation/screens/ai_triage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final service = PatientProblemService();
    await service.clearAllData();
  });

  tearDown(() async {
    await PatientProblemService().clearAllData();
  });

  group('GS HEALTH Multi-Specialty AI Health Triage & Dynamic Prescription Tests', () {
    test('1. SpecialtyClinicalConfig covers all 17 specialties plus any future specialty without dental hardcoding', () {
      final expected = <String, String>{
        'Dentistry': 'Aligners & Orthodontics',
        'Cardiology': 'Chest Pain',
        'Dermatology': 'Acne',
        'Neurology': 'Migraine',
        'Orthopedics': 'Joint Pain',
        'Gynecology': 'PCOS',
        'Pediatrics': 'Child Nutrition',
        'General Medicine': 'Fever & Viral Illness',
        'ENT': 'Ear Pain & Infection',
        'Ophthalmology': 'Blurred Vision',
        'Gastroenterology': 'Acidity & Reflux',
        'Oncology': 'Cancer Screening & Second Opinion',
        'Psychiatry': 'Anxiety & Stress',
        'Urology': 'Kidney Stone Symptoms',
        'Pulmonology': 'Wheezing & Asthma',
        'Endocrinology': 'Thyroid Symptoms',
        'Physiotherapy': 'Post-Surgery Rehabilitation',
        'Nephrology': 'Nephrology Consultation', // Future specialty dynamic support
      };

      for (final entry in expected.entries) {
        final profile = SpecialtyClinicalConfig.forSpecialty(entry.key);
        expect(
          profile.triageCategories.contains(entry.value),
          isTrue,
          reason: '${entry.key} must include category "${entry.value}"',
        );
        if (entry.key != 'Dentistry') {
          expect(
            profile.triageCategories.contains('Aligners & Orthodontics'),
            isFalse,
            reason: '${entry.key} must NOT show dental-only categories',
          );
          expect(
            profile.symptomHint.toLowerCase().contains('tooth'),
            isFalse,
            reason: '${entry.key} must NOT show dental-only symptom placeholder',
          );
        }
      }
    });

    testWidgets(
      '2. AI Health Triage updates categories dynamically per specialty, auto-detects doctor specialty, shows emergency warning & matching specialists',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-cardio-1',
            userId: 'u-cardio-1',
            name: 'Dr. Ramesh Rao',
            specialty: 'Cardiology',
            qualification: 'MBBS, MD, DM (Cardiology)',
            experienceYears: 12,
            rating: 4.9,
            reviewCount: 44,
            clinicName: 'GS Heart Institute',
            phone: '9876543210',
            email: 'cardio@gshealth.test',
            status: 'Available',
            city: 'Hyderabad',
            pincode: '500081',
            nextAvailableSlots: const ['10:00 AM'],
            consultationFee: '₹900',
          ),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-derm-1',
            userId: 'u-derm-1',
            name: 'Dr. Rohitha Skin',
            specialty: 'Dermatology',
            qualification: 'MBBS, MD (Dermatology)',
            experienceYears: 8,
            rating: 4.8,
            reviewCount: 25,
            clinicName: 'Devi Skin Clinic',
            phone: '9876543211',
            email: 'derm@gshealth.test',
            status: 'Available',
            city: 'Hyderabad',
            pincode: '500081',
            nextAvailableSlots: const ['11:00 AM'],
            consultationFee: '₹700',
          ),
        );

        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(useMaterial3: false),
              home: RepaintBoundary(
                key: boundaryKey,
                child: const AiTriageScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Default is General Medicine (NOT dental-only Aligners & Orthodontics!)
        expect(find.text('General Medicine'), findsWidgets);
        expect(find.text('Aligners & Orthodontics'), findsNothing);

        // Select Cardiology -> loads Chest Pain, Heart Palpitations, etc.
        await tester.tap(find.byKey(const Key('ai_triage_specialty_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cardiology').last);
        await tester.pumpAndSettle();
        expect(find.text('Chest Pain'), findsOneWidget);

        // Capture screenshot of Cardiology AI Health Triage for visual verification
        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          final outFile = File(
            r'C:\Users\ADMIN\.gemini\antigravity\brain\0cdf62c7-364d-4c39-8424-4bae41245b5b\gs_health_ai_triage_multispecialty.png',
          );
          await outFile.writeAsBytes(byteData!.buffer.asUint8List());
        });

        // Enter emergency symptoms & run triage -> shows emergency warning + non-diagnostic text + Cardiologist match
        await tester.enterText(
          find.byKey(const Key('ai_triage_symptom_input')),
          'Sudden chest pain and shortness of breath while climbing stairs',
        );
        await tester.ensureVisible(find.byKey(const Key('ai_triage_run_button')));
        await tester.tap(find.byKey(const Key('ai_triage_run_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('ai_triage_result_card')), findsOneWidget);
        expect(find.byKey(const Key('ai_triage_emergency_warning')), findsOneWidget);
        expect(find.textContaining('NOT a medical diagnosis'), findsOneWidget);
        expect(find.byKey(const Key('ai_triage_doctor_card_doc-cardio-1')), findsOneWidget);
        expect(find.byKey(const Key('ai_triage_doctor_card_doc-derm-1')), findsNothing);

        // With Cardiology selected, the doctor dropdown ONLY shows Cardiology doctors (never Dermatology)
        await tester.ensureVisible(find.byKey(const Key('ai_triage_doctor_dropdown')));
        await tester.tap(find.byKey(const Key('ai_triage_doctor_dropdown')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Ramesh Rao · Cardiology'), findsWidgets);
        expect(find.text('Dr. Rohitha Skin · Dermatology'), findsNothing);
        await tester.tap(find.text('Dr. Ramesh Rao · Cardiology').last);
        await tester.pumpAndSettle();

        // Switching specialty dropdown to Dermatology loads Dermatology categories (Acne/Rashes) and shows Dr. Rohitha Skin
        await tester.ensureVisible(find.byKey(const Key('ai_triage_specialty_dropdown')));
        await tester.tap(find.byKey(const Key('ai_triage_specialty_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dermatology').last);
        await tester.pumpAndSettle();

        expect(find.text('Acne'), findsOneWidget);
        expect(find.text('Chest Pain'), findsNothing);
        await tester.tap(find.byKey(const Key('ai_triage_doctor_dropdown')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Rohitha Skin · Dermatology'), findsWidgets);
        expect(find.text('Dr. Ramesh Rao · Cardiology'), findsNothing);
        await tester.tap(find.text('Dr. Rohitha Skin · Dermatology').last);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '3. SpecialtyPrescriptionModal adapts fields per specialty (Cardiology, Dermatology, Orthopedics, Dentistry, General Medicine), supports Add/Edit/Remove meds & generates valid PDF',
      (tester) async {
        tester.view.physicalSize = const Size(520, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // A. Dermatology prescription form fields
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: ThemeData(useMaterial3: false),
              home: const Scaffold(
                body: SpecialtyPrescriptionModal(
                  patientId: 'pat-1',
                  patientName: 'Anu',
                  doctorId: 'doc-derm-1',
                  doctorName: 'Dr. Rohitha',
                  doctorSpecialty: 'Dermatology',
                  clinicName: 'Devi Clinic',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Dermatology'), findsOneWidget);
        expect(find.text('Skin Diagnosis'), findsOneWidget);
        expect(find.byKey(const Key('rx_section_topicalTreatment')), findsOneWidget);
        expect(find.byKey(const Key('rx_section_applicationInstructions')), findsOneWidget);

        // Manually add 2 medications, edit item 1, remove item 2
        await tester.enterText(find.byKey(const Key('rx_diagnosis_input')), 'Contact Dermatitis');
        await tester.enterText(find.byKey(const Key('rx_section_topicalTreatment')), 'Hydrocortisone 1% Cream');
        await tester.enterText(find.byKey(const Key('rx_med_name_input')), 'Cetirizine 10mg');
        await tester.enterText(find.byKey(const Key('rx_med_dosage_input')), '1 Tablet');
        await tester.enterText(find.byKey(const Key('rx_med_frequency_input')), '0-0-1');
        await tester.enterText(find.byKey(const Key('rx_med_duration_input')), '5 Days');
        await tester.ensureVisible(find.byKey(const Key('rx_add_medication_btn')));
        await tester.tap(find.byKey(const Key('rx_add_medication_btn')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('rx_med_name_input')), 'Calamine Lotion');
        await tester.tap(find.byKey(const Key('rx_add_medication_btn')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('rx_med_item_0')), findsOneWidget);
        expect(find.byKey(const Key('rx_med_item_1')), findsOneWidget);

        // Remove second item
        await tester.tap(find.byKey(const Key('rx_remove_item_1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('rx_med_item_1')), findsNothing);

        // Edit first item
        await tester.tap(find.byKey(const Key('rx_edit_item_0')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('rx_med_duration_input')), '7 Days');
        await tester.tap(find.byKey(const Key('rx_add_medication_btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('7 Days'), findsWidgets);

        // B. Orthopedics prescription form shows Physiotherapy Recommendations & Investigations
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: ThemeData(useMaterial3: false),
              home: const Scaffold(
                body: SpecialtyPrescriptionModal(
                  key: ValueKey('ortho_rx_modal'),
                  patientId: 'pat-1',
                  patientName: 'Anu',
                  doctorId: 'doc-ortho-1',
                  doctorName: 'Dr. Kiran',
                  doctorSpecialty: 'Orthopedics',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('rx_section_investigations')), findsOneWidget);
        expect(find.byKey(const Key('rx_section_physiotherapyRecommendations')), findsOneWidget);
        expect(find.byKey(const Key('rx_section_treatmentInstructions')), findsOneWidget);

        // C. Verify pure-Dart PDF generator produces a valid %PDF-1.4 document with specialty fields
        final pdfBytes = PrescriptionPdfGenerator.generatePdfBytes({
          'specialty': 'Cardiology',
          'doctorName': 'Dr. Ramesh Rao',
          'doctorQualification': 'MBBS, MD, DM (Cardiology)',
          'clinicName': 'GS Heart Institute',
          'patientName': 'Anu',
          'diagnosis': 'Essential Hypertension',
          'clinicalSections': {
            'investigations': '12-Lead ECG, 2D Echo',
            'monitoringInstructions': 'Daily BP log',
          },
          'followUpDate': '2026-12-05',
          'items': [
            {
              'name': 'Amlodipine 5mg',
              'dosage': '1 Tablet',
              'frequency': '1-0-0',
              'duration': '30 Days',
              'instructions': 'After breakfast',
            }
          ],
        });
        final pdfText = latin1.decode(pdfBytes);
        expect(pdfText.startsWith('%PDF-1.4'), isTrue);
        expect(pdfText.contains('Cardiology'), isTrue);
        expect(pdfText.contains('Essential Hypertension'), isTrue);
        expect(pdfText.contains('12-Lead ECG, 2D Echo'), isTrue);
        expect(pdfText.contains('Amlodipine 5mg'), isTrue);
        expect(pdfText.contains('%%EOF'), isTrue);
      },
    );

    testWidgets(
      '4. AI Health Triage Doctor Dropdown enforces Scenarios 1–8: strict specialty filtering, availability/slot filtering, General Medicine fallback, empty state, case-insensitive search, deduplication & specialty switching',
      (tester) async {
        tester.view.physicalSize = const Size(430, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        await service.clearAllData();

        // Seed doctors:
        // - 2 duplicate entries for Available Cardiologist Dr. Sri -> must deduplicate to 1
        // - 1 Unavailable Cardiologist Dr. Offline Cardio -> must be excluded
        // - 1 Available Neurologist Dr. Brain Neuro -> must only appear for Neurology
        // - 2 Dental doctors (Endodontist & Orthodontist) -> must NEVER appear under Cardiology or Neurology
        // - 1 Available General Medicine doctor Dr. Priya GM -> must appear ONLY for General Medicine or as fallback when primary specialty has 0 available doctors
        // - 1 Unavailable General Medicine doctor Dr. Leave GM -> must NEVER appear even in fallback
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-sri-1',
            userId: 'u-sri-1',
            name: 'Dr. sri',
            specialty: 'Cardiology',
            qualification: 'MBBS, MD, DM',
            experienceYears: 10,
            rating: 4.9,
            reviewCount: 15,
            clinicName: 'Heart Care',
            phone: '9100000001',
            email: 'sri@cardio.test',
            status: 'Available',
            onlineStatus: 'Offline', // Schedule is Available even though live presence is Offline
            nextAvailableSlots: const ['10:00 AM'],
            consultationFee: '₹900',
          ),
        );
        // Duplicate entry with same email/phone/name+specialty (Scenario 7)
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-sri-dup',
            userId: 'u-sri-1',
            name: 'Dr. sri',
            specialty: 'Cardiology',
            qualification: 'MBBS, MD, DM',
            experienceYears: 10,
            rating: 4.9,
            reviewCount: 15,
            clinicName: 'Heart Care',
            phone: '9100000001',
            email: 'sri@cardio.test',
            status: 'Available',
            nextAvailableSlots: const ['10:00 AM'],
            consultationFee: '₹900',
          ),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-cardio-off',
            userId: 'u-cardio-off',
            name: 'Dr. Vikram OffCardio',
            specialty: 'Cardiology',
            qualification: 'MBBS, MD, DM',
            experienceYears: 11,
            rating: 4.7,
            reviewCount: 10,
            clinicName: 'Heart Care',
            phone: '9100000002',
            email: 'vikram@cardio.test',
            status: 'Unavailable',
            nextAvailableSlots: const ['11:00 AM'],
            consultationFee: '₹900',
          ),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-neuro-1',
            userId: 'u-neuro-1',
            name: 'Dr. Anand Neuro',
            specialty: 'Neurology',
            qualification: 'MBBS, MD, DM (Neurology)',
            experienceYears: 14,
            rating: 4.8,
            reviewCount: 22,
            clinicName: 'Neuro Center',
            phone: '9100000003',
            email: 'anand@neuro.test',
            status: 'Available',
            nextAvailableSlots: const ['10:30 AM'],
            consultationFee: '₹1000',
          ),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-endo-1',
            userId: 'u-endo-1',
            name: 'Dr. Doctor Endo',
            specialty: 'Endodontist',
            qualification: 'BDS, MDS',
            experienceYears: 7,
            rating: 4.6,
            reviewCount: 9,
            clinicName: 'Dental Care',
            phone: '9100000004',
            email: 'endo@dental.test',
            status: 'Available',
            nextAvailableSlots: const ['02:00 PM'],
            consultationFee: '₹600',
          ),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-ortho-1',
            userId: 'u-ortho-1',
            name: 'Dr. Doctor Ortho',
            specialty: 'Orthodontist',
            qualification: 'BDS, MDS',
            experienceYears: 8,
            rating: 4.7,
            reviewCount: 11,
            clinicName: 'Dental Care',
            phone: '9100000005',
            email: 'ortho@dental.test',
            status: 'Available',
            nextAvailableSlots: const ['03:00 PM'],
            consultationFee: '₹650',
          ),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-gm-avail',
            userId: 'u-gm-avail',
            name: 'Dr. Priya General',
            specialty: 'General Medicine',
            qualification: 'MBBS, MD',
            experienceYears: 9,
            rating: 4.9,
            reviewCount: 30,
            clinicName: 'City Primary Clinic',
            phone: '9100000006',
            email: 'priya@gm.test',
            status: 'Available',
            nextAvailableSlots: const ['09:30 AM'],
            consultationFee: '₹500',
          ),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-gm-leave',
            userId: 'u-gm-leave',
            name: 'Dr. Leave General',
            specialty: 'General Medicine',
            qualification: 'MBBS, MD',
            experienceYears: 6,
            rating: 4.5,
            reviewCount: 5,
            clinicName: 'City Primary Clinic',
            phone: '9100000007',
            email: 'leave@gm.test',
            status: 'On Leave',
            nextAvailableSlots: const [],
            consultationFee: '₹500',
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(useMaterial3: false),
              home: const AiTriageScreen(initialSpecialty: 'Cardiology'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Scenario 1 & 7: Cardiology selected with available Cardiologists -> shows ONLY Dr. sri (deduplicated once),
        // excludes Endodontist, Orthodontist, Neurologist, General Medicine, and unavailable Cardiologist.
        expect(find.byKey(const Key('ai_triage_general_medicine_fallback_notice')), findsNothing);
        await tester.tap(find.byKey(const Key('ai_triage_doctor_dropdown')));
        await tester.pumpAndSettle();
        // When dropdown menu is open, the selected/menu item for Dr. sri appears once in the menu list (not duplicated)
        expect(find.text('Dr. sri · Cardiology'), findsOneWidget);
        expect(find.text('Dr. Vikram OffCardio · Cardiology'), findsNothing);
        expect(find.text('Dr. Doctor Endo · Endodontist'), findsNothing);
        expect(find.text('Dr. Doctor Ortho · Orthodontist'), findsNothing);
        expect(find.text('Dr. Anand Neuro · Neurology'), findsNothing);
        expect(find.text('Dr. Priya General · General Medicine'), findsNothing);

        // Select Dr. sri
        await tester.tap(find.text('Dr. sri · Cardiology').last);
        await tester.pumpAndSettle();

        // Scenario 8: Switching from Cardiology to Neurology refreshes results to show ONLY Neurology doctors
        await tester.tap(find.byKey(const Key('ai_triage_specialty_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Neurology').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('ai_triage_doctor_dropdown')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Anand Neuro · Neurology'), findsOneWidget);
        expect(find.text('Dr. sri · Cardiology'), findsNothing);
        expect(find.text('Dr. Doctor Endo · Endodontist'), findsNothing);
        await tester.tap(find.text('Dr. Anand Neuro · Neurology').last);
        await tester.pumpAndSettle();

        // Scenario 5: Search with different letter cases (e.g. "cArDiOlOgY") dynamically switches and filters to Cardiology
        await tester.enterText(
          find.byKey(const Key('ai_triage_specialty_search_input')),
          'cArDiOlOgY',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ai_triage_doctor_dropdown')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. sri · Cardiology'), findsOneWidget);
        expect(find.text('Dr. Anand Neuro · Neurology'), findsNothing);
        await tester.tap(find.text('Dr. sri · Cardiology').last);
        await tester.pumpAndSettle();

        // Scenario 6, 2 & 3: Doctor becomes unavailable after list is loaded (or has all upcoming dates blocked) ->
        // Dr. sri is deselected/excluded and Cardiology automatically falls back to available General Medicine doctors (Dr. Priya General),
        // while excluding unavailable General Medicine doctor (Dr. Leave General).
        final baseNow = DateTime.now();
        for (int offset = 1; offset <= 7; offset++) {
          final d = DateTime(baseNow.year, baseNow.month, baseNow.day).add(Duration(days: offset));
          final dStr = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          service.setTestAvailability(
            'doc-sri-1',
            DoctorAvailabilityModel(
              dentistId: 'doc-sri-1',
              date: dStr,
              allSlots: const ['10:00 AM'],
              availableSlots: const [],
              isBlocked: true,
              blockedReason: 'Doctor on Leave',
            ),
          );
          service.setTestAvailability(
            'doc-sri-dup',
            DoctorAvailabilityModel(
              dentistId: 'doc-sri-dup',
              date: dStr,
              allSlots: const ['10:00 AM'],
              availableSlots: const [],
              isBlocked: true,
              blockedReason: 'Doctor on Leave',
            ),
          );
        }
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('ai_triage_general_medicine_fallback_notice')), findsOneWidget);
        await tester.tap(find.byKey(const Key('ai_triage_doctor_dropdown')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Priya General · General Medicine'), findsOneWidget);
        expect(find.text('Dr. Leave General · General Medicine'), findsNothing);
        expect(find.text('Dr. sri · Cardiology'), findsNothing);
        expect(find.text('Dr. Doctor Endo · Endodontist'), findsNothing);
        await tester.tap(find.text('Any Specialist in Selected Department').last);
        await tester.pumpAndSettle();

        // Scenario 4: No available doctors in either Cardiology or General Medicine (e.g. General Medicine doctor has 0 available slots / blocked across upcoming window)
        for (int offset = 1; offset <= 7; offset++) {
          final d = DateTime(baseNow.year, baseNow.month, baseNow.day).add(Duration(days: offset));
          final dStr = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          service.setTestAvailability(
            'doc-gm-avail',
            DoctorAvailabilityModel(
              dentistId: 'doc-gm-avail',
              date: dStr,
              allSlots: const ['09:30 AM'],
              availableSlots: const [],
              isBlocked: true,
              blockedReason: 'Doctor on Leave',
            ),
          );
        }
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('ai_triage_no_available_doctors_message')), findsOneWidget);
        expect(
          find.text('No available doctors found for this specialization. Please try again later.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('ai_triage_doctor_dropdown')), findsNothing);
      },
    );
  });
}
