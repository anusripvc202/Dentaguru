import 'medical_specialty_model.dart';

class PrescriptionSectionSchema {
  final String key;
  final String label;
  final String placeholder;
  final bool multiline;

  const PrescriptionSectionSchema({
    required this.key,
    required this.label,
    required this.placeholder,
    this.multiline = true,
  });
}

class SpecialtyPrescriptionSchema {
  final String diagnosisLabel;
  final String diagnosisPlaceholder;
  final List<PrescriptionSectionSchema> sections;
  final bool showFollowUpDate;

  const SpecialtyPrescriptionSchema({
    required this.diagnosisLabel,
    required this.diagnosisPlaceholder,
    required this.sections,
    this.showFollowUpDate = true,
  });
}

class SpecialtyClinicalProfile {
  final String code;
  final String name;
  final List<String> aliases;
  final List<String> triageCategories;
  final String symptomHint;
  final List<String> emergencyKeywords;
  final List<String> urgentKeywords;
  final String selfCareGuidance;
  final String emergencyWarning;
  final SpecialtyPrescriptionSchema prescriptionSchema;

  const SpecialtyClinicalProfile({
    required this.code,
    required this.name,
    required this.aliases,
    required this.triageCategories,
    required this.symptomHint,
    required this.emergencyKeywords,
    required this.urgentKeywords,
    required this.selfCareGuidance,
    required this.emergencyWarning,
    required this.prescriptionSchema,
  });
}

/// Central frontend multi-specialty clinical configuration powering:
/// 1. Dynamic AI Health Triage categories & specialty-contextual guidance
/// 2. Dynamic Doctor Consultation categories
/// 3. Dynamic Specialty-Specific E-Prescription forms (manual doctor entry & approval)
class SpecialtyClinicalConfig {
  SpecialtyClinicalConfig._();

  static const List<String> _universalEmergencyKeywords = [
    'chest pain',
    'chest pressure',
    'difficulty breathing',
    'cannot breathe',
    'shortness of breath',
    'unconscious',
    'passed out',
    'fainting',
    'seizure',
    'stroke',
    'slurred speech',
    'face drooping',
    'uncontrolled bleeding',
    'vomiting blood',
    'suicidal',
    'self harm',
    'anaphylaxis',
    'throat swelling',
  ];

  static const List<SpecialtyClinicalProfile> profiles = [
    SpecialtyClinicalProfile(
      code: 'DENTAL',
      name: 'Dentistry',
      aliases: [
        'dentistry',
        'general dentistry',
        'general dentist',
        'dental',
        'orthodontics',
        'orthodontist',
        'endodontics',
        'endodontist',
        'periodontics',
        'periodontist',
        'prosthodontics',
        'prosthodontist',
        'oral surgery',
        'oral & maxillofacial surgery',
        'oral surgeon',
        'pediatric dentistry',
        'pedodontics',
        'implantology',
        'cosmetic dentistry',
      ],
      triageCategories: [
        'General Dentistry',
        'Aligners & Orthodontics',
        'Root Canal Treatment',
        'Tooth Pain',
        'Gum Problems',
        'Dental Implants',
        'Oral Surgery',
      ],
      symptomHint: 'e.g. Sensitivity to cold drinks, swollen gums, or tooth discomfort when chewing...',
      emergencyKeywords: [
        'difficulty swallowing',
        'difficulty breathing',
        'facial swelling spreading',
        'uncontrolled bleeding',
        'jaw trauma',
        'knocked out tooth',
      ],
      urgentKeywords: [
        'severe toothache',
        'abscess',
        'pus',
        'swelling',
        'bleeding gums',
        'broken tooth',
        'fever',
      ],
      selfCareGuidance:
          'Keep the area clean with gentle warm salt-water rinses and avoid very hot, cold, or hard foods until evaluated by a dentist.',
      emergencyWarning:
          'Seek immediate emergency medical care if you develop rapid facial/neck swelling, difficulty swallowing or breathing, high fever, or uncontrolled bleeding.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Dental Diagnosis',
        diagnosisPlaceholder: 'e.g. Acute Pulpitis (Tooth #36), Gingivitis, Impacted Molar...',
        sections: [
          PrescriptionSectionSchema(
            key: 'dentalTreatment',
            label: 'Dental Treatment',
            placeholder: 'e.g. Root Canal Therapy, Scaling & Polishing, Composite Restoration...',
          ),
          PrescriptionSectionSchema(
            key: 'procedureInstructions',
            label: 'Dental Procedure Instructions',
            placeholder: 'e.g. Soft diet for 24 hrs, warm saline rinse after 24 hrs, gentle brushing...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'CARDIO',
      name: 'Cardiology',
      aliases: [
        'cardiology',
        'cardiologist',
        'interventional cardiology',
        'electrophysiology',
        'heart',
        'cardiac',
      ],
      triageCategories: [
        'Chest Pain',
        'Heart Palpitations',
        'High Blood Pressure',
        'Shortness of Breath',
        'Heart-related Symptoms',
      ],
      symptomHint: 'e.g. Chest tightness on exertion, fluttering heartbeat, or elevated blood pressure readings...',
      emergencyKeywords: [
        'chest pain',
        'chest pressure',
        'pain radiating to arm',
        'pain radiating to jaw',
        'shortness of breath',
        'fainting',
        'syncope',
        'crushing chest',
      ],
      urgentKeywords: [
        'palpitations',
        'high blood pressure',
        'dizziness',
        'leg swelling',
        'irregular heartbeat',
      ],
      selfCareGuidance:
          'Rest calmly, avoid strenuous exertion, monitor blood pressure and pulse if available, and keep your current medication list ready for your cardiologist.',
      emergencyWarning:
          'EMERGENCY: If you have sudden or severe chest pain/pressure, pain spreading to the arm/neck/jaw, severe shortness of breath, cold sweats, or fainting, call emergency services or visit the nearest ER immediately.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Clinical Diagnosis',
        diagnosisPlaceholder: 'e.g. Essential Hypertension, Paroxysmal Palpitations, CAD Follow-up...',
        sections: [
          PrescriptionSectionSchema(
            key: 'investigations',
            label: 'Investigations',
            placeholder: 'e.g. 12-Lead ECG, 2D Echocardiography, Lipid Profile, HbA1c, TMT...',
          ),
          PrescriptionSectionSchema(
            key: 'monitoringInstructions',
            label: 'Monitoring Instructions',
            placeholder: 'e.g. Home BP & pulse log twice daily, low-sodium diet, warning signs...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'DERM',
      name: 'Dermatology',
      aliases: [
        'dermatology',
        'dermatologist',
        'clinical dermatology',
        'cosmetology',
        'trichology',
        'skin',
        'venereology',
      ],
      triageCategories: [
        'Acne',
        'Skin Allergies',
        'Rashes',
        'Hair Loss',
        'Skin Infections',
      ],
      symptomHint: 'e.g. Itchy red rash on arms, recurring facial acne, scalp flaking, or hair thinning...',
      emergencyKeywords: [
        'swollen lips',
        'swollen tongue',
        'throat swelling',
        'difficulty breathing',
        'blistering all over',
        'anaphylaxis',
      ],
      urgentKeywords: [
        'spreading rash',
        'pus',
        'oozing',
        'severe itching',
        'hives',
        'skin infection',
        'fever',
      ],
      selfCareGuidance:
          'Avoid scratching or applying unprescribed steroid/home remedies. Use a mild fragrance-free cleanser and note any new skincare products, foods, or medicines.',
      emergencyWarning:
          'Seek immediate emergency care if a rash or allergic reaction occurs with lip/face/throat swelling, trouble breathing, dizziness, or widespread painful blistering.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Skin Diagnosis',
        diagnosisPlaceholder: 'e.g. Acne Vulgaris, Contact Dermatitis, Tinea Corporis, Telogen Effluvium...',
        sections: [
          PrescriptionSectionSchema(
            key: 'topicalTreatment',
            label: 'Topical Treatment',
            placeholder: 'e.g. Topical gel/cream, medicated cleanser, broad-spectrum SPF 50 sunscreen...',
          ),
          PrescriptionSectionSchema(
            key: 'applicationInstructions',
            label: 'Application Instructions',
            placeholder: 'e.g. Apply pea-sized thin layer on clean dry skin at night; avoid sun exposure...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'NEURO',
      name: 'Neurology',
      aliases: [
        'neurology',
        'neurologist',
        'stroke medicine',
        'epileptology',
        'neurosciences',
        'brain',
        'nerve',
      ],
      triageCategories: [
        'Headaches',
        'Migraine',
        'Seizures',
        'Nerve Pain',
        'Dizziness',
      ],
      symptomHint: 'e.g. Throbbing one-sided headache with light sensitivity, tingling in hands, or recurrent dizziness...',
      emergencyKeywords: [
        'sudden weakness',
        'face drooping',
        'slurred speech',
        'seizure',
        'worst headache',
        'thunderclap headache',
        'loss of consciousness',
        'vision loss',
        'confusion',
        'stroke',
      ],
      urgentKeywords: [
        'persistent migraine',
        'numbness',
        'tingling',
        'balance loss',
        'vertigo',
        'nerve pain',
      ],
      selfCareGuidance:
          'Rest in a quiet, dimly lit room for headaches, stay hydrated, avoid driving if experiencing dizziness or aura, and track triggers and frequency.',
      emergencyWarning:
          'EMERGENCY: Seek immediate emergency care for sudden face drooping, arm/leg weakness, slurred speech, a new or prolonged seizure, sudden severe headache, or sudden confusion.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Neurological Diagnosis',
        diagnosisPlaceholder: 'e.g. Migraine without Aura, Peripheral Neuropathy, Vertigo Evaluation...',
        sections: [
          PrescriptionSectionSchema(
            key: 'investigations',
            label: 'Neurological Investigations',
            placeholder: 'e.g. MRI Brain, CT Scan, EEG, Nerve Conduction Study, Vitamin B12...',
          ),
          PrescriptionSectionSchema(
            key: 'monitoringInstructions',
            label: 'Symptom & Safety Instructions',
            placeholder: 'e.g. Headache/seizure diary, sleep routine, trigger avoidance, driving precautions...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'ORTHO',
      name: 'Orthopedics',
      aliases: [
        'orthopedics',
        'orthopaedics',
        'orthopedist',
        'joint replacement',
        'spine surgery',
        'sports medicine',
        'bone',
      ],
      triageCategories: [
        'Joint Pain',
        'Back Pain',
        'Bone Fractures',
        'Arthritis',
        'Muscle Pain',
      ],
      symptomHint: 'e.g. Knee pain while climbing stairs, lower back stiffness, or ankle swelling after a twist...',
      emergencyKeywords: [
        'visible bone',
        'open fracture',
        'cannot move limb',
        'loss of bowel',
        'loss of bladder',
        'numbness in legs',
        'severe deformity',
      ],
      urgentKeywords: [
        'fracture',
        'unable to bear weight',
        'swollen joint',
        'locked knee',
        'radiating back pain',
        'dislocation',
      ],
      selfCareGuidance:
          'Protect and rest the affected joint or limb, apply a wrapped cold pack for 15 minutes if swollen, and avoid heavy lifting or twisting movements until examined.',
      emergencyWarning:
          'Seek immediate emergency care for suspected fractures with deformity, open wounds over bone, inability to move a limb, or back pain with leg numbness or bladder/bowel changes.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Diagnosis',
        diagnosisPlaceholder: 'e.g. Osteoarthritis Knee, Lumbar Spondylosis, Ankle Ligament Sprain...',
        sections: [
          PrescriptionSectionSchema(
            key: 'investigations',
            label: 'Investigations',
            placeholder: 'e.g. X-Ray AP/Lateral, MRI Knee/Spine, DEXA Scan, Vitamin D & Calcium...',
          ),
          PrescriptionSectionSchema(
            key: 'physiotherapyRecommendations',
            label: 'Physiotherapy Recommendations',
            placeholder: 'e.g. Range-of-motion exercises, quadriceps/core strengthening, hot/cold therapy...',
          ),
          PrescriptionSectionSchema(
            key: 'treatmentInstructions',
            label: 'Treatment Instructions',
            placeholder: 'e.g. Knee brace/support use, weight-bearing guidance, posture advice...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'GYNEC',
      name: 'Gynecology',
      aliases: [
        'gynecology',
        'gynaecology',
        'gynecologist',
        'obstetrics',
        'obstetrics & gynecology',
        'obgyn',
        'fetal medicine',
        'reproductive medicine',
      ],
      triageCategories: [
        'Menstrual Problems',
        'Pregnancy-related Concerns',
        'PCOS',
        'Pelvic Pain',
      ],
      symptomHint: 'e.g. Irregular cycles, lower pelvic discomfort, or prenatal questions...',
      emergencyKeywords: [
        'heavy bleeding in pregnancy',
        'severe abdominal pain in pregnancy',
        'fainting',
        'reduced fetal movement',
        'severe headache in pregnancy',
        'high bp in pregnancy',
      ],
      urgentKeywords: [
        'pelvic pain',
        'abnormal bleeding',
        'fever with pelvic pain',
        'pregnancy vomiting',
      ],
      selfCareGuidance:
          'Keep a note of your last menstrual period (LMP), cycle duration, any test results, and current medications to share with your gynecologist.',
      emergencyWarning:
          'Seek immediate emergency medical care for heavy vaginal bleeding, severe pelvic/abdominal pain, fainting, or any bleeding, severe headache, or reduced fetal movement during pregnancy.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Gynecological / Obstetric Diagnosis',
        diagnosisPlaceholder: 'e.g. PCOS, Dysmenorrhea, Routine Antenatal Care, Iron-Deficiency Anemia...',
        sections: [
          PrescriptionSectionSchema(
            key: 'investigations',
            label: 'Investigations & Scans',
            placeholder: 'e.g. Pelvic Ultrasound, CBC, Thyroid Profile, Hormonal Panel, Urine Routine...',
          ),
          PrescriptionSectionSchema(
            key: 'careInstructions',
            label: 'Care & Lifestyle Instructions',
            placeholder: 'e.g. Nutrition plan, cycle tracking, prenatal precautions & warning signs...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'PEDIA',
      name: 'Pediatrics',
      aliases: [
        'pediatrics',
        'paediatrics',
        'pediatrician',
        'child health',
        'neonatology',
        'pediatric critical care',
      ],
      triageCategories: [
        'Fever',
        'Cough',
        'Cold',
        'Child Nutrition',
        'Child Development',
      ],
      symptomHint: 'e.g. Child has mild fever since yesterday, persistent cough, or poor appetite...',
      emergencyKeywords: [
        'difficulty breathing',
        'blue lips',
        'unresponsive',
        'seizure',
        'stiff neck',
        'refusing all fluids',
        'no wet diapers',
        'high fever 104',
      ],
      urgentKeywords: [
        'high fever',
        'persistent vomiting',
        'ear tugging',
        'wheezing',
        'rash with fever',
        'dehydration',
      ],
      selfCareGuidance:
          'Keep the child well hydrated with oral fluids, dress in light breathable clothing, monitor temperature regularly, and record child age/weight for accurate dosing.',
      emergencyWarning:
          'Seek immediate emergency care if a child has trouble breathing, bluish lips, unresponsiveness, seizures, signs of dehydration, or fever in an infant under 3 months.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Pediatric Diagnosis',
        diagnosisPlaceholder: 'e.g. Viral Upper Respiratory Tract Infection, Acute Febrile Illness...',
        sections: [
          PrescriptionSectionSchema(
            key: 'symptoms',
            label: 'Symptoms & Weight / Vitals',
            placeholder: 'e.g. Child weight (kg), temperature, hydration status, key symptoms...',
          ),
          PrescriptionSectionSchema(
            key: 'careInstructions',
            label: 'Nutrition, Hydration & Care Instructions',
            placeholder: 'e.g. ORS hydration schedule, fever sponging, growth/immunization notes...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'GEN_MED',
      name: 'General Medicine',
      aliases: [
        'general medicine',
        'internal medicine',
        'family medicine',
        'general physician',
        'primary care',
      ],
      triageCategories: [
        'Fever & Viral Illness',
        'Body Ache & Fatigue',
        'Blood Pressure & Diabetes Check',
        'Digestive Discomfort',
        'Preventive Health Checkup',
      ],
      symptomHint: 'e.g. Low-grade fever with body ache for 2 days, persistent fatigue, or blood sugar fluctuations...',
      emergencyKeywords: [
        'chest pain',
        'difficulty breathing',
        'confusion',
        'unconscious',
        'severe dehydration',
        'high fever 104',
        'uncontrolled bleeding',
      ],
      urgentKeywords: [
        'persistent fever',
        'vomiting',
        'severe weakness',
        'dizziness',
        'high bp',
        'low blood sugar',
      ],
      selfCareGuidance:
          'Stay well hydrated, rest adequately, monitor temperature/BP/blood glucose if relevant, and avoid taking unprescribed antibiotics.',
      emergencyWarning:
          'Seek immediate emergency care for chest pain, severe shortness of breath, sudden confusion, fainting, stiff neck with fever, or uncontrollable bleeding.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Clinical Diagnosis',
        diagnosisPlaceholder: 'e.g. Viral Fever, Type 2 Diabetes Follow-up, Acute Gastroenteritis...',
        sections: [
          PrescriptionSectionSchema(
            key: 'symptoms',
            label: 'Symptoms',
            placeholder: 'e.g. Chief complaints, duration, vitals (BP, Temp, Pulse, SpO2)...',
          ),
          PrescriptionSectionSchema(
            key: 'labTests',
            label: 'Lab Tests',
            placeholder: 'e.g. CBC, CRP, Fasting Blood Sugar, HbA1c, LFT, KFT, Urine Routine...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'ENT',
      name: 'ENT',
      aliases: [
        'ent',
        'otorhinolaryngology',
        'ear nose throat',
        'ear, nose & throat',
        'otolaryngology',
      ],
      triageCategories: [
        'Ear Pain & Infection',
        'Sinus & Nasal Congestion',
        'Sore Throat & Tonsils',
        'Hearing Issues',
        'Vertigo & Balance',
      ],
      symptomHint: 'e.g. Ear fullness or ache, blocked sinuses, sore throat while swallowing, or spinning dizziness...',
      emergencyKeywords: [
        'difficulty breathing',
        'difficulty swallowing saliva',
        'drooling',
        'severe nosebleed',
        'sudden hearing loss',
        'neck swelling',
      ],
      urgentKeywords: [
        'ear discharge',
        'high fever with sore throat',
        'severe ear pain',
        'vertigo',
        'hoarseness',
      ],
      selfCareGuidance:
          'Avoid inserting cotton buds or objects into the ear canal. Warm saline gargles and gentle steam inhalation may help temporarily until examined.',
      emergencyWarning:
          'Seek immediate emergency care for trouble breathing or swallowing, severe uncontrolled nosebleed, sudden complete hearing loss, or rapidly worsening neck swelling.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'ENT Diagnosis',
        diagnosisPlaceholder: 'e.g. Acute Otitis Media, Allergic Rhinitis, Acute Tonsillitis, BPPV...',
        sections: [
          PrescriptionSectionSchema(
            key: 'investigations',
            label: 'ENT Investigations',
            placeholder: 'e.g. Pure Tone Audiometry (PTA), Nasal Endoscopy, X-Ray/CT PNS...',
          ),
          PrescriptionSectionSchema(
            key: 'careInstructions',
            label: 'Local Care & Precautions',
            placeholder: 'e.g. Keep ear dry, saline nasal spray/steam inhalation, voice rest...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'OPHTHAL',
      name: 'Ophthalmology',
      aliases: [
        'ophthalmology',
        'ophthalmologist',
        'eye',
        'vision sciences',
        'retina',
        'cataract',
      ],
      triageCategories: [
        'Blurred Vision',
        'Eye Redness & Irritation',
        'Eye Pain & Dryness',
        'Cataract / Refractive Check',
        'Watery Eyes & Discharge',
      ],
      symptomHint: 'e.g. Blurred distance vision, dry gritty eyes after screen use, or redness in one eye...',
      emergencyKeywords: [
        'sudden vision loss',
        'chemical in eye',
        'eye injury',
        'flashes of light',
        'curtain over vision',
        'severe eye pain with nausea',
      ],
      urgentKeywords: [
        'eye pain',
        'light sensitivity',
        'pus discharge',
        'double vision',
        'swollen eyelid',
      ],
      selfCareGuidance:
          'Do not rub your eyes, remove contact lenses if irritated, and avoid using leftover or steroid eye drops without examination.',
      emergencyWarning:
          'Seek immediate emergency eye care for sudden vision loss, chemical splashes, eye trauma, sudden flashes/floaters, or severe eye pain with nausea.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Ophthalmic Diagnosis',
        diagnosisPlaceholder: 'e.g. Dry Eye Syndrome, Allergic Conjunctivitis, Myopia / Refractive Error...',
        sections: [
          PrescriptionSectionSchema(
            key: 'eyeDropsAndTopicals',
            label: 'Eye Drops / Ointments',
            placeholder: 'e.g. Lubricating drops, antibiotic drops (specify OD / OS / OU)...',
          ),
          PrescriptionSectionSchema(
            key: 'investigations',
            label: 'Vision & Eye Investigations',
            placeholder: 'e.g. Visual Acuity, IOP (Tonometry), Slit-Lamp Exam, OCT, Refraction...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'GASTRO',
      name: 'Gastroenterology',
      aliases: [
        'gastroenterology',
        'gastroenterologist',
        'hepatology',
        'digestive',
        'stomach',
        'liver',
      ],
      triageCategories: [
        'Abdominal Pain',
        'Acidity & Reflux',
        'Bloating & Indigestion',
        'Liver & Gallbladder Symptoms',
        'Bowel Habit Changes',
      ],
      symptomHint: 'e.g. Burning sensation after meals, upper abdominal discomfort, or persistent bloating...',
      emergencyKeywords: [
        'vomiting blood',
        'black tarry stools',
        'blood in stool',
        'severe rigid abdomen',
        'unable to keep fluids down',
      ],
      urgentKeywords: [
        'jaundice',
        'persistent vomiting',
        'severe abdominal pain',
        'unexplained weight loss',
        'dehydration',
      ],
      selfCareGuidance:
          'Eat light, bland, non-spicy meals, stay hydrated with water or oral rehydration fluids, and avoid NSAID painkillers or alcohol until evaluated.',
      emergencyWarning:
          'Seek immediate emergency care for vomiting blood, black/bloody stools, severe unrelenting abdominal pain, yellowing of eyes/skin with fever, or severe dehydration.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Gastroenterology Diagnosis',
        diagnosisPlaceholder: 'e.g. GERD, Acute Gastritis, IBS, Fatty Liver Follow-up...',
        sections: [
          PrescriptionSectionSchema(
            key: 'investigations',
            label: 'Lab Tests & Endoscopy / Imaging',
            placeholder: 'e.g. Ultrasound Abdomen, LFT, H. pylori test, Upper GI Endoscopy...',
          ),
          PrescriptionSectionSchema(
            key: 'dietInstructions',
            label: 'Dietary & Lifestyle Advice',
            placeholder: 'e.g. Small frequent meals, avoid spicy/fatty food, avoid lying down right after meals...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'ONCO',
      name: 'Oncology',
      aliases: [
        'oncology',
        'oncologist',
        'medical oncology',
        'surgical oncology',
        'radiation oncology',
        'cancer care',
      ],
      triageCategories: [
        'Unexplained Lump or Swelling',
        'Persistent Fatigue or Weight Loss',
        'Cancer Screening & Second Opinion',
        'Post-Treatment Follow-up',
        'Biopsy / Pathology Report Review',
      ],
      symptomHint: 'e.g. Painless persistent lump, oncology second opinion, or post-treatment follow-up...',
      emergencyKeywords: [
        'fever during chemotherapy',
        'neutropenic fever',
        'severe shortness of breath',
        'uncontrolled bleeding',
        'confusion',
      ],
      urgentKeywords: [
        'fever',
        'severe nausea',
        'persistent pain',
        'new lump',
        'unexplained bleeding',
      ],
      selfCareGuidance:
          'Keep all prior pathology, biopsy, imaging (CT/PET/MRI), and treatment summaries organized for your oncology consultation.',
      emergencyWarning:
          'Seek immediate emergency care if undergoing cancer treatment and developing fever (>=100.4°F / 38°C), chills, severe breathlessness, bleeding, or confusion.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Oncology Clinical Assessment',
        diagnosisPlaceholder: 'e.g. Post-Chemotherapy Follow-up, Oncology Staging & Supportive Care...',
        sections: [
          PrescriptionSectionSchema(
            key: 'investigations',
            label: 'Staging, Lab & Imaging Workup',
            placeholder: 'e.g. CBC with Differential, Tumor Markers, CT/PET-CT, Biopsy review...',
          ),
          PrescriptionSectionSchema(
            key: 'supportiveCare',
            label: 'Supportive Care & Monitoring Instructions',
            placeholder: 'e.g. Infection precautions, hydration, antiemetic/pain monitoring...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'PSYCH',
      name: 'Psychiatry',
      aliases: [
        'psychiatry',
        'psychiatrist',
        'mental health',
        'behavioral sciences',
        'psychology',
      ],
      triageCategories: [
        'Anxiety & Stress',
        'Sleep Disorders & Insomnia',
        'Persistent Low Mood',
        'Focus & Behavioral Concerns',
        'Counseling & Medication Review',
      ],
      symptomHint: 'e.g. Difficulty falling asleep for weeks, frequent anxiety, or persistent low mood...',
      emergencyKeywords: [
        'suicidal',
        'self harm',
        'hurt myself',
        'harm others',
        'hallucinations',
      ],
      urgentKeywords: [
        'severe insomnia',
        'panic attacks',
        'acute distress',
        'medication side effects',
      ],
      selfCareGuidance:
          'Reach out to a trusted family member or friend, keep a consistent sleep routine, and do not abruptly stop prescribed psychiatric medications without consulting your doctor.',
      emergencyWarning:
          'EMERGENCY: If you or someone you know has thoughts of self-harm or suicide, please contact emergency services or a 24/7 crisis helpline immediately.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Psychiatric Assessment',
        diagnosisPlaceholder: 'e.g. Generalized Anxiety, Insomnia, Depressive Episode Follow-up...',
        sections: [
          PrescriptionSectionSchema(
            key: 'therapyPlan',
            label: 'Psychotherapy / Counseling Plan',
            placeholder: 'e.g. CBT sessions, sleep hygiene therapy, stress management plan...',
          ),
          PrescriptionSectionSchema(
            key: 'monitoringInstructions',
            label: 'Monitoring & Safety Instructions',
            placeholder: 'e.g. Do not stop medication abruptly; monitor mood/sleep; emergency helpline...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'URO',
      name: 'Urology',
      aliases: [
        'urology',
        'urologist',
        'renal sciences',
        'kidney',
        'urinary',
      ],
      triageCategories: [
        'Urinary Pain or Burning',
        'Frequent Urination',
        'Kidney Stone Symptoms',
        'Lower Abdominal / Flank Pain',
        'Prostate / Urological Review',
      ],
      symptomHint: 'e.g. Burning sensation during urination, side/flank pain, or frequent nighttime urination...',
      emergencyKeywords: [
        'unable to pass urine',
        'acute urinary retention',
        'severe testicular pain',
        'heavy blood in urine',
        'flank pain with high fever',
      ],
      urgentKeywords: [
        'blood in urine',
        'fever with burning urine',
        'severe flank pain',
        'vomiting with kidney pain',
      ],
      selfCareGuidance:
          'Maintain adequate water intake unless fluid-restricted by a physician, and bring any recent ultrasound or urine reports.',
      emergencyWarning:
          'Seek immediate emergency care if completely unable to urinate, experiencing sudden severe testicular pain, or flank pain with high fever and chills.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Urological Diagnosis',
        diagnosisPlaceholder: 'e.g. Uncomplicated UTI, Renal Calculi, BPH Follow-up...',
        sections: [
          PrescriptionSectionSchema(
            key: 'investigations',
            label: 'Urological Investigations',
            placeholder: 'e.g. Urine Routine & Culture, Ultrasound KUB, Serum Creatinine, PSA...',
          ),
          PrescriptionSectionSchema(
            key: 'careInstructions',
            label: 'Hydration & Care Instructions',
            placeholder: 'e.g. Daily hydration target, dietary stone precautions...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'PULMO',
      name: 'Pulmonology',
      aliases: [
        'pulmonology',
        'pulmonologist',
        'respiratory medicine',
        'chest',
        'lungs',
        'asthma',
      ],
      triageCategories: [
        'Persistent Cough',
        'Shortness of Breath',
        'Wheezing & Asthma',
        'Chest Tightness',
        'Sleep Apnea & Snoring',
      ],
      symptomHint: 'e.g. Cough lasting over 2 weeks, wheezing at night, or breathlessness on walking...',
      emergencyKeywords: [
        'severe shortness of breath',
        'cannot speak full sentences',
        'blue lips',
        'coughing up blood',
        'low oxygen',
        'spo2 below 90',
      ],
      urgentKeywords: [
        'wheezing',
        'asthma flare',
        'fever with cough',
        'shortness of breath',
        'chest tightness',
      ],
      selfCareGuidance:
          'Avoid smoke, dust, and triggers, sit upright if breathless, check SpO2 if an oximeter is available, and bring any current inhalers.',
      emergencyWarning:
          'EMERGENCY: Seek immediate emergency care for severe difficulty breathing, inability to speak in full sentences, bluish lips/nails, coughing up blood, or SpO2 below 92%.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Pulmonary Diagnosis',
        diagnosisPlaceholder: 'e.g. Bronchial Asthma, Acute Bronchitis, COPD Maintenance...',
        sections: [
          PrescriptionSectionSchema(
            key: 'investigations',
            label: 'Pulmonary Investigations',
            placeholder: 'e.g. Chest X-Ray, Spirometry / PFT, Sputum Culture, HRCT Chest...',
          ),
          PrescriptionSectionSchema(
            key: 'inhalerAndMonitoring',
            label: 'Inhaler Technique & Monitoring Instructions',
            placeholder: 'e.g. Spacer use, rinse mouth after steroid inhaler, peak flow/SpO2 log...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'ENDO',
      name: 'Endocrinology',
      aliases: [
        'endocrinology',
        'endocrinologist',
        'diabetes',
        'diabetology',
        'thyroid',
        'metabolism',
      ],
      triageCategories: [
        'Diabetes & Blood Sugar',
        'Thyroid Symptoms',
        'Hormonal Imbalance',
        'Weight & Metabolism Concerns',
        'Fatigue & Vitamin Deficiency',
      ],
      symptomHint: 'e.g. Fluctuating blood glucose levels, unexplained weight changes, or persistent tiredness...',
      emergencyKeywords: [
        'very low blood sugar',
        'blood sugar below 60',
        'confusion',
        'fruity breath',
        'blood sugar above 400',
        'fainting',
      ],
      urgentKeywords: [
        'high blood sugar',
        'dizziness',
        'palpitations',
        'excessive thirst',
        'vomiting with diabetes',
      ],
      selfCareGuidance:
          'Keep a log of fasting and post-meal glucose readings (if diabetic) and bring your latest HbA1c, TSH, and medication list.',
      emergencyWarning:
          'Seek immediate emergency care for severe hypoglycemia (confusion, fainting) or very high blood sugar with vomiting, abdominal pain, or rapid breathing.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Endocrine Diagnosis',
        diagnosisPlaceholder: 'e.g. Type 2 Diabetes Mellitus, Hypothyroidism, Vitamin D Deficiency...',
        sections: [
          PrescriptionSectionSchema(
            key: 'labTests',
            label: 'Hormone & Metabolic Lab Tests',
            placeholder: 'e.g. HbA1c, Fasting/PP Glucose, TSH/Free T3/T4, Vitamin D, Lipid Profile...',
          ),
          PrescriptionSectionSchema(
            key: 'monitoringInstructions',
            label: 'Glucose / Diet & Monitoring Plan',
            placeholder: 'e.g. SMBG schedule, diet/exercise plan, hypoglycemia action instructions...',
          ),
        ],
      ),
    ),
    SpecialtyClinicalProfile(
      code: 'PHYSIO',
      name: 'Physiotherapy',
      aliases: [
        'physiotherapy',
        'physiotherapist',
        'physical therapy',
        'rehabilitation',
        'rehab',
      ],
      triageCategories: [
        'Back & Neck Stiffness',
        'Joint Mobility & Rehab',
        'Post-Surgery Rehabilitation',
        'Sports Injury Recovery',
        'Posture & Muscle Strain',
      ],
      symptomHint: 'e.g. Stiff neck from desk posture, knee stiffness after surgery, or shoulder strain...',
      emergencyKeywords: [
        'sudden limb weakness',
        'loss of bladder',
        'loss of bowel',
        'suspected fracture',
      ],
      urgentKeywords: [
        'sharp radiating pain',
        'numbness',
        'acute joint swelling',
        'unable to walk',
      ],
      selfCareGuidance:
          'Avoid movements that trigger sharp pain, apply gentle ice or heat as tolerated, and bring any orthopedic imaging or post-operative notes.',
      emergencyWarning:
          'Seek immediate medical care if pain occurs with sudden numbness/weakness in limbs, loss of bowel/bladder control, or suspected fracture.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Rehabilitation Assessment',
        diagnosisPlaceholder: 'e.g. Cervical Strain, Post-ACL Rehabilitation, Frozen Shoulder...',
        sections: [
          PrescriptionSectionSchema(
            key: 'physiotherapyRecommendations',
            label: 'Physiotherapy & Exercise Protocol',
            placeholder: 'e.g. Stretching & strengthening sets, modality (TENS/IFT/Ultrasound), frequency...',
          ),
          PrescriptionSectionSchema(
            key: 'treatmentInstructions',
            label: 'Home Precautions & Ergonomics',
            placeholder: 'e.g. Posture correction, activity limits, ice/heat application schedule...',
          ),
        ],
      ),
    ),
  ];

  /// Resolve clinical profile for ANY existing or newly created future medical specialty.
  static SpecialtyClinicalProfile forSpecialty(String? specialty) {
    final clean = (specialty ?? '').trim();
    if (clean.isEmpty || clean.toLowerCase() == 'all' || clean.toLowerCase() == 'all specialties') {
      return forSpecialty('General Medicine');
    }
    final lower = clean.toLowerCase();
    // 1. Exact match on name, code, or alias first (prevents 'ent' matching substring of 'dentistry')
    for (final profile in profiles) {
      if (profile.name.toLowerCase() == lower ||
          profile.code.toLowerCase() == lower ||
          profile.aliases.contains(lower)) {
        return profile;
      }
    }
    // 2. Partial/substring match for compound specialty names (e.g. 'Interventional Cardiology')
    for (final profile in profiles) {
      if (profile.aliases.any((a) => a.length >= 4 && lower.contains(a))) {
        return profile;
      }
    }
    return SpecialtyClinicalProfile(
      code: clean.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_'),
      name: clean,
      aliases: [lower],
      triageCategories: [
        '$clean Consultation',
        'Symptom Evaluation',
        'Pain or Discomfort',
        'Diagnostic & Report Review',
        'Follow-up Care',
      ],
      symptomHint: 'e.g. Describe your symptoms, duration, and relevant history for $clean...',
      emergencyKeywords: const ['chest pain', 'difficulty breathing', 'unconscious', 'seizure', 'uncontrolled bleeding'],
      urgentKeywords: const ['high fever', 'severe pain', 'persistent vomiting', 'fainting', 'swelling'],
      selfCareGuidance:
          'Note when your symptoms started, what improves or worsens them, and keep any prior medical reports ready for your $clean specialist.',
      emergencyWarning:
          'Seek immediate emergency medical care for chest pain, severe difficulty breathing, fainting, sudden weakness/numbness, seizures, or uncontrolled bleeding.',
      prescriptionSchema: SpecialtyPrescriptionSchema(
        diagnosisLabel: 'Clinical Diagnosis',
        diagnosisPlaceholder: 'e.g. Enter $clean clinical assessment or diagnosis...',
        sections: const [
          PrescriptionSectionSchema(
            key: 'symptoms',
            label: 'Clinical Findings / Symptoms',
            placeholder: 'e.g. Presenting symptoms, clinical observations, vitals...',
          ),
          PrescriptionSectionSchema(
            key: 'investigations',
            label: 'Investigations / Lab Tests',
            placeholder: 'e.g. Recommended laboratory tests or imaging...',
          ),
          PrescriptionSectionSchema(
            key: 'treatmentInstructions',
            label: 'Treatment & Care Instructions',
            placeholder: 'e.g. Specific treatment plan, lifestyle advice, precautions...',
          ),
        ],
      ),
    );
  }

  /// Dynamic list of all selectable specialties (database specialties + built-in clinical profiles + doctor specialties).
  static List<String> allSelectableSpecialties({
    List<MedicalSpecialtyModel> activeSpecialties = const [],
    Iterable<String> registeredDoctorSpecialties = const [],
  }) {
    final seen = <String>{};
    final result = <String>[];

    void addUnique(String raw) {
      final clean = raw.trim();
      if (clean.isEmpty || clean.toLowerCase() == 'all' || clean.toLowerCase() == 'all specialties') return;
      if (seen.add(clean.toLowerCase())) {
        result.add(clean);
      }
    }

    for (final s in activeSpecialties) {
      if (s.isActive) addUnique(s.name);
    }
    for (final p in profiles) {
      addUnique(p.name);
    }
    for (final dSpec in registeredDoctorSpecialties) {
      final resolved = forSpecialty(dSpec);
      addUnique(resolved.name);
    }
    return result;
  }

  /// Local deterministic specialty-contextual AI triage fallback (never gives a definitive diagnosis).
  static Map<String, dynamic> analyzeLocally({
    required String specialty,
    required String category,
    required String symptoms,
    required String severity,
    required String duration,
  }) {
    final profile = forSpecialty(specialty);
    final lower = '${symptoms.trim()} $category'.toLowerCase();
    final sevLower = severity.trim().toLowerCase();

    final hasEmergency = [
      ..._universalEmergencyKeywords,
      ...profile.emergencyKeywords,
    ].any((kw) => lower.contains(kw));
    final hasUrgent = profile.urgentKeywords.any((kw) => lower.contains(kw));

    String urgencyLevel;
    String urgency;
    bool isEmergency = false;
    String summary;

    if (hasEmergency || sevLower == 'severe') {
      isEmergency = hasEmergency;
      urgencyLevel = isEmergency ? 'Emergency' : 'Urgent';
      urgency = isEmergency
          ? 'Emergency Evaluation Recommended Immediately'
          : 'Urgent Specialist Care Recommended (< 24 hrs)';
      summary = isEmergency
          ? 'Your reported symptoms in ${profile.name} ($category) include potential emergency warning signs that warrant immediate in-person medical evaluation.'
          : 'Severe ${profile.name.toLowerCase()} symptoms ($category) lasting $duration warrant prompt specialist consultation within 24 hours.';
    } else if (sevLower == 'moderate' || hasUrgent) {
      urgencyLevel = 'Soon';
      urgency = 'Specialist Consultation Recommended (24–72 hrs)';
      summary =
          'Your symptoms under ${profile.name} ($category) should be evaluated by a qualified ${profile.name} specialist within 24–72 hours for proper clinical assessment.';
    } else {
      urgencyLevel = 'Routine';
      urgency = 'Routine Evaluation Suggested';
      summary =
          'Mild symptoms under ${profile.name} ($category) can typically be reviewed at a routine specialist consultation. Monitor for any worsening signs.';
    }

    return {
      'specialty': profile.name,
      'specialtyCode': profile.code,
      'category': category,
      'severity': severity,
      'duration': duration,
      'urgencyLevel': urgencyLevel,
      'urgency': urgency,
      'isEmergency': isEmergency,
      'disclaimer':
          'Informational triage guidance only — this is NOT a medical diagnosis. Please consult a qualified doctor for clinical evaluation and treatment.',
      'clinicalSummary': summary,
      'recommendedSpecialty': profile.name,
      'selfCareGuidance': profile.selfCareGuidance,
      'emergencyWarning': profile.emergencyWarning,
    };
  }
}
