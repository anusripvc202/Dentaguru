import 'package:flutter/material.dart';

class MedicalSpecialtyModel {
  final String id;
  final String code;
  final String name;
  final String department;
  final String description;
  final String iconName;
  final String defaultQualifications;
  final List<String> consultationTypes;
  final List<String> subSpecialties;
  final bool isActive;
  final int displayOrder;

  const MedicalSpecialtyModel({
    required this.id,
    required this.code,
    required this.name,
    required this.department,
    required this.description,
    this.iconName = 'medical_services',
    this.defaultQualifications = 'MBBS, MD',
    this.consultationTypes = const ['General Consultation'],
    this.subSpecialties = const [],
    this.isActive = true,
    this.displayOrder = 100,
  });

  MedicalSpecialtyModel copyWith({
    String? id,
    String? code,
    String? name,
    String? department,
    String? description,
    String? iconName,
    String? defaultQualifications,
    List<String>? consultationTypes,
    List<String>? subSpecialties,
    bool? isActive,
    int? displayOrder,
  }) {
    return MedicalSpecialtyModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      department: department ?? this.department,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      defaultQualifications: defaultQualifications ?? this.defaultQualifications,
      consultationTypes: consultationTypes ?? this.consultationTypes,
      subSpecialties: subSpecialties ?? this.subSpecialties,
      isActive: isActive ?? this.isActive,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }

  IconData get iconData {
    switch (code.toUpperCase()) {
      case 'GEN_MED':
        return Icons.medical_services_rounded;
      case 'CARDIO':
        return Icons.monitor_heart_rounded;
      case 'DERM':
        return Icons.face_retouching_natural_rounded;
      case 'NEURO':
        return Icons.psychology_rounded;
      case 'ORTHO':
        return Icons.accessibility_new_rounded;
      case 'PEDIA':
        return Icons.child_care_rounded;
      case 'GYNEC':
        return Icons.pregnant_woman_rounded;
      case 'ENT':
        return Icons.hearing_rounded;
      case 'OPHTHAL':
        return Icons.visibility_rounded;
      case 'ONCO':
        return Icons.biotech_rounded;
      case 'URO':
        return Icons.water_drop_rounded;
      case 'PSYCH':
        return Icons.self_improvement_rounded;
      case 'GASTRO':
        return Icons.medication_liquid_rounded;
      case 'PULMO':
        return Icons.air_rounded;
      case 'ENDO':
        return Icons.bloodtype_rounded;
      case 'DENTAL':
        return Icons.health_and_safety_rounded;
      default:
        return Icons.local_hospital_rounded;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'department': department,
        'description': description,
        'icon': iconName,
        'default_qualifications': defaultQualifications,
        'consultation_types': consultationTypes,
        'sub_specialties': subSpecialties,
        'is_active': isActive,
        'display_order': displayOrder,
      };

  factory MedicalSpecialtyModel.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString().trim();
    final code = (json['code'] ??
            name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_'))
        .toString()
        .trim();

    List<String> parseStringList(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      return [];
    }

    final parsedConsultations = parseStringList(
      json['consultation_types'] ?? json['consultationTypes'],
    );
    final parsedSubs = parseStringList(
      json['sub_specialties'] ?? json['subSpecialties'],
    );

    return MedicalSpecialtyModel(
      id: (json['id'] ?? 'spec-${code.toLowerCase()}').toString(),
      code: code,
      name: name,
      department: (json['department'] ?? 'Department of $name').toString(),
      description: (json['description'] ?? '$name clinical care & consultations.').toString(),
      iconName: (json['icon'] ?? json['iconName'] ?? 'medical_services').toString(),
      defaultQualifications: (json['default_qualifications'] ??
              json['defaultQualifications'] ??
              getDefaultQualificationForSpecialty(name))
          .toString(),
      consultationTypes: parsedConsultations.isNotEmpty
          ? parsedConsultations
          : ['General Consultation', '$name Specialist Consultation', 'Follow-up Visit'],
      subSpecialties: parsedSubs,
      isActive: json['is_active'] != null
          ? json['is_active'] == true
          : (json['isActive'] != null ? json['isActive'] == true : true),
      displayOrder: int.tryParse((json['display_order'] ?? json['displayOrder'] ?? 100).toString()) ?? 100,
    );
  }

  static const List<String> _dentalKeywords = [
    'dentistry',
    'general dentistry',
    'orthodontics',
    'endodontics',
    'periodontics',
    'prosthodontics',
    'pediatric dentistry',
    'cosmetic dentistry',
    'oral surgery',
    'oral & maxillofacial surgery',
    'maxillofacial',
    'dental',
    'root canal',
    'tooth',
    'implantology',
  ];

  static bool isDentalSpecialty(String specialty) {
    final s = specialty.trim().toLowerCase();
    if (s.isEmpty) return true;
    return _dentalKeywords.any((k) => s.contains(k));
  }

  static bool matchesSpecialtyFilter(
    String doctorSpecialty,
    String selectedFilter, {
    List<MedicalSpecialtyModel>? specialties,
  }) {
    final filterClean = selectedFilter.trim();
    if (filterClean.isEmpty || filterClean.toLowerCase() == 'all') return true;

    final fLower = filterClean.toLowerCase();
    final dLower = (doctorSpecialty.trim().isEmpty ? 'General Dentistry' : doctorSpecialty.trim()).toLowerCase();

    if (dLower == fLower || dLower.contains(fLower) || fLower.contains(dLower)) {
      return true;
    }

    if (fLower == 'dentistry' || fLower == 'dental') {
      return isDentalSpecialty(dLower);
    }

    if (specialties != null) {
      for (final spec in specialties) {
        if (spec.name.toLowerCase() == fLower) {
          for (final sub in spec.subSpecialties) {
            final subLower = sub.toLowerCase();
            if (dLower == subLower || dLower.contains(subLower)) {
              return true;
            }
          }
        }
      }
    }

    return false;
  }

  static String getDefaultQualificationForSpecialty(String specialty) {
    final lower = specialty.trim().toLowerCase();
    if (isDentalSpecialty(lower)) return 'BDS, MDS';
    if (lower.contains('cardio')) return 'MBBS, MD, DM (Cardiology)';
    if (lower.contains('derma')) return 'MBBS, MD (Dermatology)';
    if (lower.contains('neuro')) return 'MBBS, MD, DM (Neurology)';
    if (lower.contains('ortho')) return 'MBBS, MS (Orthopedics)';
    if (lower.contains('pedia')) return 'MBBS, MD (Pediatrics)';
    if (lower.contains('gynec') || lower.contains('obstet')) return 'MBBS, MS (Obstetrics & Gynecology)';
    if (lower == 'ent' || lower.contains('otolaryng') || lower.contains('ear')) return 'MBBS, MS (ENT)';
    if (lower.contains('ophthal') || lower.contains('eye')) return 'MBBS, MS (Ophthalmology)';
    if (lower.contains('onco')) return 'MBBS, MD, DM (Oncology)';
    if (lower.contains('uro')) return 'MBBS, MS, MCh (Urology)';
    if (lower.contains('psych')) return 'MBBS, MD (Psychiatry)';
    if (lower.contains('gastro')) return 'MBBS, MD, DM (Gastroenterology)';
    if (lower.contains('pulmo') || lower.contains('respir')) return 'MBBS, MD (Pulmonology)';
    if (lower.contains('endocrin') || lower.contains('diabet')) return 'MBBS, MD, DM (Endocrinology)';
    if (lower.contains('general medicine') || lower.contains('internal medicine')) {
      return 'MBBS, MD (General Medicine)';
    }
    return 'MBBS, MD';
  }

  static List<String> getConsultationTypesForSpecialty(
    String specialty, {
    List<MedicalSpecialtyModel>? specialties,
  }) {
    final list = specialties ?? defaultSpecialties;
    final lower = specialty.trim().toLowerCase();

    if (isDentalSpecialty(lower)) {
      final dentalSpec = list.firstWhere(
        (s) => s.code == 'DENTAL' || s.name.toLowerCase() == 'dentistry',
        orElse: () => defaultSpecialties.last,
      );
      return dentalSpec.consultationTypes;
    }

    for (final spec in list) {
      if (spec.name.toLowerCase() == lower ||
          lower.contains(spec.name.toLowerCase()) ||
          spec.subSpecialties.any((sub) => sub.toLowerCase() == lower)) {
        if (spec.consultationTypes.isNotEmpty) {
          return spec.consultationTypes;
        }
      }
    }

    final cleanSpec = specialty.trim().isNotEmpty ? specialty.trim() : 'Medical';
    return [
      'General Consultation',
      '$cleanSpec Specialist Evaluation',
      'Diagnostic & Lab Report Review',
      'Treatment Plan & Prescription Follow-up',
      'Preventive Screening & Second Opinion',
    ];
  }

  static const List<MedicalSpecialtyModel> defaultSpecialties = [
    MedicalSpecialtyModel(
      id: 'spec-general-medicine',
      code: 'GEN_MED',
      name: 'General Medicine',
      department: 'Department of Internal & General Medicine',
      description: 'Primary care, internal medicine, acute & chronic illnesses, fever, and preventive health checkups.',
      iconName: 'medical_services',
      defaultQualifications: 'MBBS, MD (General Medicine)',
      consultationTypes: [
        'General Consultation',
        'Fever & Viral Infection',
        'Diabetes & Blood Pressure Review',
        'Preventive Health Checkup',
        'Chronic Illness Follow-up',
      ],
      subSpecialties: ['Internal Medicine', 'Family Medicine'],
      isActive: true,
      displayOrder: 1,
    ),
    MedicalSpecialtyModel(
      id: 'spec-cardiology',
      code: 'CARDIO',
      name: 'Cardiology',
      department: 'Department of Cardiology & Vascular Sciences',
      description: 'Diagnosis and treatment of heart conditions, hypertension, arrhythmias, and cardiovascular diseases.',
      iconName: 'MonitorHeart',
      defaultQualifications: 'MBBS, MD, DM (Cardiology)',
      consultationTypes: [
        'General Consultation',
        'Cardiac Evaluation & ECG Review',
        'Hypertension & Lipid Management',
        'Chest Pain & Arrhythmia Assessment',
        'Post-Angioplasty Follow-up',
      ],
      subSpecialties: ['Interventional Cardiology', 'Electrophysiology'],
      isActive: true,
      displayOrder: 2,
    ),
    MedicalSpecialtyModel(
      id: 'spec-dermatology',
      code: 'DERM',
      name: 'Dermatology',
      department: 'Department of Dermatology, Venereology & Cosmetology',
      description: 'Skin, hair, nail disorders, acne, eczema, psoriasis, and clinical dermatological procedures.',
      iconName: 'FaceRetouchingNatural',
      defaultQualifications: 'MBBS, MD (Dermatology)',
      consultationTypes: [
        'General Consultation',
        'Skin & Acne Consultation',
        'Hair Fall & Scalp Evaluation',
        'Allergy & Rash Treatment',
        'Eczema / Psoriasis Care',
      ],
      subSpecialties: ['Clinical Dermatology', 'Cosmetology', 'Trichology'],
      isActive: true,
      displayOrder: 3,
    ),
    MedicalSpecialtyModel(
      id: 'spec-neurology',
      code: 'NEURO',
      name: 'Neurology',
      department: 'Department of Neurology & Neurosciences',
      description: 'Disorders of the brain, spinal cord, peripheral nerves, migraine, epilepsy, and stroke care.',
      iconName: 'Psychology',
      defaultQualifications: 'MBBS, MD, DM (Neurology)',
      consultationTypes: [
        'General Consultation',
        'Migraine & Headache Clinic',
        'Epilepsy & Seizure Management',
        'Stroke Recovery & Neuropathy',
        'Memory & Movement Disorders',
      ],
      subSpecialties: ['Stroke Medicine', 'Epileptology'],
      isActive: true,
      displayOrder: 4,
    ),
    MedicalSpecialtyModel(
      id: 'spec-orthopedics',
      code: 'ORTHO',
      name: 'Orthopedics',
      department: 'Department of Orthopedics & Joint Replacement',
      description: 'Bone, joint, ligament, spine, sports injuries, arthritis, and fracture management.',
      iconName: 'AccessibilityNew',
      defaultQualifications: 'MBBS, MS (Orthopedics)',
      consultationTypes: [
        'General Consultation',
        'Bone & Joint Consultation',
        'Back & Spine Pain Evaluation',
        'Sports Injury & Ligament Care',
        'Arthritis & Knee Replacement Review',
      ],
      subSpecialties: ['Joint Replacement', 'Spine Surgery', 'Sports Medicine'],
      isActive: true,
      displayOrder: 5,
    ),
    MedicalSpecialtyModel(
      id: 'spec-pediatrics',
      code: 'PEDIA',
      name: 'Pediatrics',
      department: 'Department of Pediatrics & Child Health',
      description: 'Comprehensive medical care for infants, children, and adolescents including vaccinations and growth tracking.',
      iconName: 'ChildCare',
      defaultQualifications: 'MBBS, MD (Pediatrics), DCH',
      consultationTypes: [
        'General Consultation',
        'Child Health & Growth Checkup',
        'Vaccination & Immunization',
        'Pediatric Fever & Infection',
        'Newborn & Infant Nutrition Care',
      ],
      subSpecialties: ['Neonatology', 'Pediatric Critical Care'],
      isActive: true,
      displayOrder: 6,
    ),
    MedicalSpecialtyModel(
      id: 'spec-gynecology',
      code: 'GYNEC',
      name: 'Gynecology',
      department: 'Department of Obstetrics & Gynecology',
      description: 'Women\'s reproductive health, pregnancy care, prenatal checkups, PCOS, and gynecological wellness.',
      iconName: 'PregnantWoman',
      defaultQualifications: 'MBBS, MS / DGO (Obstetrics & Gynecology)',
      consultationTypes: [
        'General Consultation',
        'Antenatal / Pregnancy Checkup',
        'PCOS & Hormonal Evaluation',
        'Menstrual Health Clinic',
        'Postnatal & Fertility Care',
      ],
      subSpecialties: ['Obstetrics', 'Fetal Medicine', 'Reproductive Medicine'],
      isActive: true,
      displayOrder: 7,
    ),
    MedicalSpecialtyModel(
      id: 'spec-ent',
      code: 'ENT',
      name: 'ENT',
      department: 'Department of Otorhinolaryngology (Ear, Nose & Throat)',
      description: 'Ear infections, hearing loss, sinusitis, tonsillitis, throat disorders, and vertigo management.',
      iconName: 'Hearing',
      defaultQualifications: 'MBBS, MS (ENT)',
      consultationTypes: [
        'General Consultation',
        'Ear Pain & Hearing Assessment',
        'Sinusitis & Nasal Allergy',
        'Throat & Tonsil Infection',
        'Vertigo & Balance Evaluation',
      ],
      subSpecialties: ['Otology', 'Rhinology', 'Laryngology'],
      isActive: true,
      displayOrder: 8,
    ),
    MedicalSpecialtyModel(
      id: 'spec-ophthalmology',
      code: 'OPHTHAL',
      name: 'Ophthalmology',
      department: 'Department of Ophthalmology & Vision Sciences',
      description: 'Comprehensive eye exams, cataract, glaucoma, retina care, and vision correction.',
      iconName: 'Visibility',
      defaultQualifications: 'MBBS, MS (Ophthalmology)',
      consultationTypes: [
        'General Consultation',
        'Comprehensive Eye & Vision Exam',
        'Cataract & Lens Consultation',
        'Retina & Diabetic Eye Screening',
        'Glaucoma & Dry Eye Care',
      ],
      subSpecialties: ['Retina', 'Cornea', 'Glaucoma'],
      isActive: true,
      displayOrder: 9,
    ),
    MedicalSpecialtyModel(
      id: 'spec-oncology',
      code: 'ONCO',
      name: 'Oncology',
      department: 'Department of Oncology & Cancer Care',
      description: 'Medical, surgical, and radiation oncology consultations, cancer screening, and follow-up care.',
      iconName: 'Biotech',
      defaultQualifications: 'MBBS, MD, DM (Medical Oncology)',
      consultationTypes: [
        'General Consultation',
        'Cancer Screening & Prevention',
        'Chemotherapy / Immunotherapy Review',
        'Second Opinion & Tumor Evaluation',
        'Oncology Follow-up Care',
      ],
      subSpecialties: ['Medical Oncology', 'Surgical Oncology', 'Radiation Oncology'],
      isActive: true,
      displayOrder: 10,
    ),
    MedicalSpecialtyModel(
      id: 'spec-urology',
      code: 'URO',
      name: 'Urology',
      department: 'Department of Urology & Renal Sciences',
      description: 'Kidney stones, urinary tract infections, prostate health, and reconstructive urology.',
      iconName: 'WaterDrop',
      defaultQualifications: 'MBBS, MS, MCh (Urology)',
      consultationTypes: [
        'General Consultation',
        'Kidney Stone Evaluation',
        'Urinary Tract Infection (UTI)',
        'Prostate Health Screening',
        'Bladder & Renal Follow-up',
      ],
      subSpecialties: ['Endourology', 'Andrology', 'Uro-Oncology'],
      isActive: true,
      displayOrder: 11,
    ),
    MedicalSpecialtyModel(
      id: 'spec-psychiatry',
      code: 'PSYCH',
      name: 'Psychiatry',
      department: 'Department of Psychiatry & Behavioral Sciences',
      description: 'Mental health consultations, anxiety, depression, stress management, sleep disorders, and counseling.',
      iconName: 'SelfImprovement',
      defaultQualifications: 'MBBS, MD (Psychiatry)',
      consultationTypes: [
        'General Consultation',
        'Anxiety & Stress Management',
        'Depression & Mood Clinic',
        'Sleep Disorder Evaluation',
        'Behavioral & Counseling Support',
      ],
      subSpecialties: ['Adult Psychiatry', 'Child & Adolescent Psychiatry'],
      isActive: true,
      displayOrder: 12,
    ),
    MedicalSpecialtyModel(
      id: 'spec-gastroenterology',
      code: 'GASTRO',
      name: 'Gastroenterology',
      department: 'Department of Gastroenterology & Hepatology',
      description: 'Digestive tract, stomach, liver, pancreas, acidity, IBS, and endoscopy consultations.',
      iconName: 'MedicationLiquid',
      defaultQualifications: 'MBBS, MD, DM (Gastroenterology)',
      consultationTypes: [
        'General Consultation',
        'Acidity, Reflux & Ulcer Care',
        'Liver & Hepatology Evaluation',
        'IBS & Digestive Disorder Clinic',
        'Endoscopy / Colonoscopy Review',
      ],
      subSpecialties: ['Hepatology', 'Therapeutic Endoscopy'],
      isActive: true,
      displayOrder: 13,
    ),
    MedicalSpecialtyModel(
      id: 'spec-pulmonology',
      code: 'PULMO',
      name: 'Pulmonology',
      department: 'Department of Pulmonology & Respiratory Medicine',
      description: 'Asthma, COPD, bronchitis, sleep apnea, lung infections, and allergy management.',
      iconName: 'Air',
      defaultQualifications: 'MBBS, MD (Pulmonary Medicine)',
      consultationTypes: [
        'General Consultation',
        'Asthma & Respiratory Allergy Clinic',
        'Chronic Cough & COPD Care',
        'Sleep Apnea & Breathing Study',
        'Post-Infection Lung Recovery',
      ],
      subSpecialties: ['Interventional Pulmonology', 'Sleep Medicine'],
      isActive: true,
      displayOrder: 14,
    ),
    MedicalSpecialtyModel(
      id: 'spec-endocrinology',
      code: 'ENDO',
      name: 'Endocrinology',
      department: 'Department of Endocrinology, Diabetes & Metabolism',
      description: 'Diabetes mellitus, thyroid disorders, hormonal imbalances, osteoporosis, and metabolic care.',
      iconName: 'Bloodtype',
      defaultQualifications: 'MBBS, MD, DM (Endocrinology)',
      consultationTypes: [
        'General Consultation',
        'Comprehensive Diabetes Management',
        'Thyroid Disorder Clinic',
        'PCOS & Adrenal Hormone Review',
        'Metabolic & Bone Density Care',
      ],
      subSpecialties: ['Diabetology', 'Thyroid & Metabolic Medicine'],
      isActive: true,
      displayOrder: 15,
    ),
    MedicalSpecialtyModel(
      id: 'spec-dentistry',
      code: 'DENTAL',
      name: 'Dentistry',
      department: 'Department of Dental Sciences & Oral Healthcare',
      description: 'General dentistry, orthodontics, endodontics, root canal, periodontics, prosthodontics, and oral surgery.',
      iconName: 'HealthAndSafety',
      defaultQualifications: 'BDS, MDS',
      consultationTypes: [
        'General Consultation',
        'Dental Pain / Toothache',
        'Tooth Decay / Cavity',
        'Root Canal Consultation',
        'Orthodontics / Braces',
        'Periodontics / Gum Care',
        'Tooth Extraction',
        'Dental Cleaning & Scaling',
      ],
      subSpecialties: [
        'General Dentistry',
        'Orthodontics',
        'Endodontics',
        'Periodontics',
        'Prosthodontics',
        'Pediatric Dentistry',
        'Cosmetic Dentistry',
        'Oral & Maxillofacial Surgery',
        'Oral Surgery',
      ],
      isActive: true,
      displayOrder: 16,
    ),
  ];
}