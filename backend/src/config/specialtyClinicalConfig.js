/**
 * GS HEALTH — Multi-Specialty Clinical Configuration (Single Backend Source of Truth)
 * Powers dynamic AI Health Triage categories, specialty-contextual triage analysis,
 * and dynamic specialty-specific E-Prescription form schemas for ALL existing and future specialties.
 */

const SPECIALTY_CONFIGS = [
    {
        code: 'DENTAL',
        name: 'Dentistry',
        aliases: [
            'dentistry', 'general dentistry', 'general dentist', 'dental',
            'orthodontics', 'orthodontist', 'endodontics', 'endodontist',
            'periodontics', 'periodontist', 'prosthodontics', 'prosthodontist',
            'oral surgery', 'oral & maxillofacial surgery', 'oral surgeon',
            'pediatric dentistry', 'pedodontics', 'implantology', 'cosmetic dentistry'
        ],
        triageCategories: [
            'General Dentistry',
            'Aligners & Orthodontics',
            'Root Canal Treatment',
            'Tooth Pain',
            'Gum Problems',
            'Dental Implants',
            'Oral Surgery'
        ],
        symptomHint: 'e.g. Sensitivity to cold drinks, swollen gums, or tooth discomfort when chewing...',
        emergencyKeywords: ['difficulty swallowing', 'difficulty breathing', 'facial swelling spreading', 'uncontrolled bleeding', 'jaw trauma', 'knocked out tooth'],
        urgentKeywords: ['severe toothache', 'abscess', 'pus', 'swelling', 'bleeding gums', 'broken tooth', 'fever'],
        selfCareGuidance: 'Keep the area clean with gentle warm salt-water rinses and avoid very hot, cold, or hard foods until evaluated.',
        emergencyWarning: 'Seek immediate emergency medical care if you develop rapid facial/neck swelling, difficulty swallowing or breathing, high fever, or uncontrolled bleeding.',
        prescriptionSchema: {
            diagnosisLabel: 'Dental Diagnosis',
            sections: [
                { key: 'dentalTreatment', label: 'Dental Treatment', placeholder: 'e.g. Root Canal Therapy, Scaling & Polishing, Tooth Extraction...', multiline: true },
                { key: 'procedureInstructions', label: 'Dental Procedure Instructions', placeholder: 'e.g. Post-procedure care, soft diet, warm saline rinse after 24 hrs...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'CARDIO',
        name: 'Cardiology',
        aliases: ['cardiology', 'cardiologist', 'interventional cardiology', 'electrophysiology', 'heart', 'cardiac'],
        triageCategories: [
            'Chest Pain',
            'Heart Palpitations',
            'High Blood Pressure',
            'Shortness of Breath',
            'Heart-related Symptoms'
        ],
        symptomHint: 'e.g. Chest tightness on exertion, fluttering heartbeat, elevated blood pressure readings...',
        emergencyKeywords: ['chest pain', 'chest pressure', 'pain radiating to arm', 'pain radiating to jaw', 'shortness of breath', 'fainting', 'syncope', 'crushing chest', 'sweating with chest'],
        urgentKeywords: ['palpitations', 'high blood pressure', 'bp 180', 'dizziness', 'leg swelling', 'irregular heartbeat'],
        selfCareGuidance: 'Rest calmly, avoid strenuous exertion, monitor your blood pressure and pulse if available, and keep a list of your current medications ready for the cardiologist.',
        emergencyWarning: 'EMERGENCY: If you have sudden or severe chest pain/pressure, pain spreading to the arm/neck/jaw, severe shortness of breath, cold sweats, or fainting, call emergency services or go to the nearest ER immediately.',
        prescriptionSchema: {
            diagnosisLabel: 'Clinical Diagnosis',
            sections: [
                { key: 'investigations', label: 'Investigations', placeholder: 'e.g. 12-Lead ECG, 2D Echocardiography, Lipid Profile, Troponin, TMT...', multiline: true },
                { key: 'monitoringInstructions', label: 'Monitoring Instructions', placeholder: 'e.g. Daily BP & pulse log, low-sodium diet, weight monitoring, warning signs...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'DERM',
        name: 'Dermatology',
        aliases: ['dermatology', 'dermatologist', 'clinical dermatology', 'cosmetology', 'trichology', 'skin', 'venereology'],
        triageCategories: [
            'Acne',
            'Skin Allergies',
            'Rashes',
            'Hair Loss',
            'Skin Infections'
        ],
        symptomHint: 'e.g. Itchy red rash on arms, recurring facial acne, scalp flaking or hair thinning...',
        emergencyKeywords: ['swollen lips', 'swollen tongue', 'throat swelling', 'difficulty breathing', 'blistering all over', 'spreading red streaks with fever', 'anaphylaxis'],
        urgentKeywords: ['spreading rash', 'pus', 'oozing', 'severe itching', 'hives', 'skin infection', 'fever'],
        selfCareGuidance: 'Avoid scratching or applying unprescribed steroid/home remedies. Use a mild fragrance-free cleanser and note any new skincare products, foods, or medications.',
        emergencyWarning: 'Seek immediate emergency care if a rash or allergic reaction is accompanied by lip/face/throat swelling, trouble breathing, dizziness, or widespread painful blistering.',
        prescriptionSchema: {
            diagnosisLabel: 'Skin Diagnosis',
            sections: [
                { key: 'topicalTreatment', label: 'Topical Treatment', placeholder: 'e.g. Topical cream, ointment, medicated cleanser, sunscreen SPF 50...', multiline: true },
                { key: 'applicationInstructions', label: 'Application Instructions', placeholder: 'e.g. Apply a thin layer on clean dry skin at night; avoid sun exposure...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'NEURO',
        name: 'Neurology',
        aliases: ['neurology', 'neurologist', 'stroke medicine', 'epileptology', 'neurosciences', 'brain', 'nerve'],
        triageCategories: [
            'Headaches',
            'Migraine',
            'Seizures',
            'Nerve Pain',
            'Dizziness'
        ],
        symptomHint: 'e.g. Throbbing one-sided headache with light sensitivity, tingling in hands, or recurrent dizziness...',
        emergencyKeywords: ['sudden weakness', 'face drooping', 'slurred speech', 'seizure', 'worst headache', 'thunderclap headache', 'loss of consciousness', 'vision loss', 'confusion', 'stroke'],
        urgentKeywords: ['persistent migraine', 'numbness', 'tingling', 'balance loss', 'vertigo', 'memory loss', 'nerve pain'],
        selfCareGuidance: 'Rest in a quiet, dimly lit room if experiencing a headache, stay hydrated, avoid driving if dizzy or experiencing visual aura, and track symptom triggers and duration.',
        emergencyWarning: 'EMERGENCY: Seek immediate emergency care for sudden face drooping, arm/leg weakness, slurred speech, a new or prolonged seizure, sudden severe "worst-ever" headache, or sudden confusion.',
        prescriptionSchema: {
            diagnosisLabel: 'Neurological Diagnosis',
            sections: [
                { key: 'investigations', label: 'Neurological Investigations', placeholder: 'e.g. MRI Brain, CT Scan, EEG, Nerve Conduction Study (NCS), Vitamin B12...', multiline: true },
                { key: 'monitoringInstructions', label: 'Symptom & Safety Instructions', placeholder: 'e.g. Maintain headache/seizure diary, sleep hygiene, driving precautions...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'ORTHO',
        name: 'Orthopedics',
        aliases: ['orthopedics', 'orthopaedics', 'orthopedist', 'joint replacement', 'spine surgery', 'sports medicine', 'bone'],
        triageCategories: [
            'Joint Pain',
            'Back Pain',
            'Bone Fractures',
            'Arthritis',
            'Muscle Pain'
        ],
        symptomHint: 'e.g. Knee pain while climbing stairs, lower back stiffness, or ankle swelling after a twist...',
        emergencyKeywords: ['visible bone', 'open fracture', 'cannot move limb', 'loss of bowel', 'loss of bladder', 'numbness in legs', 'severe deformity', 'heavy trauma'],
        urgentKeywords: ['fracture', 'unable to bear weight', 'swollen joint', 'locked knee', 'radiating back pain', 'dislocation'],
        selfCareGuidance: 'Protect and rest the affected joint/limb, apply a cold pack wrapped in cloth for 15 minutes if swollen, and avoid heavy lifting or twisting movements until examined.',
        emergencyWarning: 'Seek immediate emergency care for suspected fractures with deformity, open wounds over bone, inability to move a limb, or back pain with leg numbness or bladder/bowel changes.',
        prescriptionSchema: {
            diagnosisLabel: 'Diagnosis',
            sections: [
                { key: 'investigations', label: 'Investigations', placeholder: 'e.g. X-Ray AP/Lateral, MRI Knee/Spine, DEXA Scan, Serum Calcium/Vitamin D...', multiline: true },
                { key: 'physiotherapyRecommendations', label: 'Physiotherapy Recommendations', placeholder: 'e.g. Range-of-motion exercises, core strengthening, hot/cold therapy protocol...', multiline: true },
                { key: 'treatmentInstructions', label: 'Treatment Instructions', placeholder: 'e.g. Brace/splint use, weight-bearing limits, ergonomic posture advice...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'GYNEC',
        name: 'Gynecology',
        aliases: ['gynecology', 'gynaecology', 'gynecologist', 'obstetrics', 'obstetrics & gynecology', 'obgyn', 'fetal medicine', 'reproductive medicine'],
        triageCategories: [
            'Menstrual Problems',
            'Pregnancy-related Concerns',
            'PCOS',
            'Pelvic Pain'
        ],
        symptomHint: 'e.g. Irregular cycles, lower pelvic discomfort, or prenatal questions...',
        emergencyKeywords: ['heavy bleeding in pregnancy', 'severe abdominal pain in pregnancy', 'fainting', 'soaking pads every hour', 'reduced fetal movement', 'severe headache in pregnancy', 'high bp in pregnancy'],
        urgentKeywords: ['pelvic pain', 'missed period with pain', 'abnormal bleeding', 'fever with pelvic pain', 'pregnancy vomiting'],
        selfCareGuidance: 'Keep a note of your last menstrual period (LMP), cycle duration, any pregnancy test results, and current medications to share with your gynecologist.',
        emergencyWarning: 'Seek immediate emergency medical care for heavy vaginal bleeding, severe pelvic/abdominal pain, dizziness/fainting, or any bleeding/severe headache/reduced baby movement during pregnancy.',
        prescriptionSchema: {
            diagnosisLabel: 'Gynecological / Obstetric Diagnosis',
            sections: [
                { key: 'investigations', label: 'Investigations & Scans', placeholder: 'e.g. Pelvic Ultrasound, CBC, Thyroid Profile, HbA1c, Hormonal Panel...', multiline: true },
                { key: 'careInstructions', label: 'Care & Lifestyle Instructions', placeholder: 'e.g. Prenatal nutrition, cycle tracking, warning signs to watch...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'PEDIA',
        name: 'Pediatrics',
        aliases: ['pediatrics', 'paediatrics', 'pediatrician', 'child health', 'neonatology', 'pediatric critical care'],
        triageCategories: [
            'Fever',
            'Cough',
            'Cold',
            'Child Nutrition',
            'Child Development'
        ],
        symptomHint: 'e.g. Child has mild fever since yesterday, persistent cough, or poor appetite...',
        emergencyKeywords: ['difficulty breathing', 'blue lips', 'unresponsive', 'seizure', 'stiff neck', 'refusing all fluids', 'no wet diapers', 'infant under 3 months with fever', 'high fever 104'],
        urgentKeywords: ['high fever', 'persistent vomiting', 'ear tugging', 'wheezing', 'rash with fever', 'dehydration'],
        selfCareGuidance: 'Keep the child well hydrated with oral fluids, dress in light breathable clothing, monitor temperature regularly, and record weight/age for accurate pediatrician evaluation.',
        emergencyWarning: 'Seek immediate emergency care if a child has trouble breathing, bluish lips, persistent drowsiness/unresponsiveness, seizures, signs of dehydration, or fever in an infant under 3 months.',
        prescriptionSchema: {
            diagnosisLabel: 'Pediatric Diagnosis',
            sections: [
                { key: 'symptoms', label: 'Symptoms & Weight / Vitals', placeholder: 'e.g. Child weight (kg), temperature, hydration status, key symptoms...', multiline: true },
                { key: 'careInstructions', label: 'Nutrition, Hydration & Care Instructions', placeholder: 'e.g. ORS hydration schedule, fever sponging, immunization/growth guidance...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'GEN_MED',
        name: 'General Medicine',
        aliases: ['general medicine', 'internal medicine', 'family medicine', 'general physician', 'primary care'],
        triageCategories: [
            'Fever & Viral Illness',
            'Body Ache & Fatigue',
            'Blood Pressure & Diabetes Check',
            'Digestive Discomfort',
            'Preventive Health Checkup'
        ],
        symptomHint: 'e.g. Low-grade fever with body ache for 2 days, persistent fatigue, or blood sugar fluctuations...',
        emergencyKeywords: ['chest pain', 'difficulty breathing', 'confusion', 'unconscious', 'severe dehydration', 'high fever 104', 'bluish lips', 'uncontrolled bleeding'],
        urgentKeywords: ['persistent fever', 'vomiting', 'severe weakness', 'dizziness', 'high bp', 'low blood sugar'],
        selfCareGuidance: 'Stay well hydrated, rest adequately, monitor temperature/blood pressure/blood glucose if relevant, and avoid self-medicating with antibiotics.',
        emergencyWarning: 'Seek immediate emergency medical attention for chest pain, severe shortness of breath, sudden confusion, fainting, stiff neck with fever, or uncontrollable bleeding.',
        prescriptionSchema: {
            diagnosisLabel: 'Clinical Diagnosis',
            sections: [
                { key: 'symptoms', label: 'Symptoms', placeholder: 'e.g. Chief complaints, duration, vitals (BP, Temp, SpO2, Pulse)...', multiline: true },
                { key: 'labTests', label: 'Lab Tests', placeholder: 'e.g. CBC, CRP, Fasting Blood Sugar, HbA1c, LFT, KFT, Urine Routine...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'ENT',
        name: 'ENT',
        aliases: ['ent', 'otorhinolaryngology', 'ear nose throat', 'ear, nose & throat', 'otolaryngology'],
        triageCategories: [
            'Ear Pain & Infection',
            'Sinus & Nasal Congestion',
            'Sore Throat & Tonsils',
            'Hearing Issues',
            'Vertigo & Balance'
        ],
        symptomHint: 'e.g. Ear fullness or ache, blocked sinuses, sore throat while swallowing, or spinning dizziness...',
        emergencyKeywords: ['difficulty breathing', 'difficulty swallowing saliva', 'drooling', 'severe nosebleed', 'sudden hearing loss', 'neck swelling'],
        urgentKeywords: ['ear discharge', 'high fever with sore throat', 'severe ear pain', 'vertigo', 'hoarseness'],
        selfCareGuidance: 'Avoid inserting cotton buds or sharp objects into the ear canal. Warm saline gargles and steam inhalation may provide temporary comfort until examination.',
        emergencyWarning: 'Seek immediate emergency care for trouble breathing or swallowing, severe uncontrolled nosebleed, sudden complete hearing loss, or rapidly worsening neck swelling.',
        prescriptionSchema: {
            diagnosisLabel: 'ENT Diagnosis',
            sections: [
                { key: 'investigations', label: 'ENT Investigations', placeholder: 'e.g. Pure Tone Audiometry (PTA), Nasal Endoscopy, X-Ray/CT PNS...', multiline: true },
                { key: 'careInstructions', label: 'Local Care & Precautions', placeholder: 'e.g. Keep ear dry, saline nasal spray/steam instructions, voice rest...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'OPHTHAL',
        name: 'Ophthalmology',
        aliases: ['ophthalmology', 'ophthalmologist', 'eye', 'vision sciences', 'retina', 'cataract'],
        triageCategories: [
            'Blurred Vision',
            'Eye Redness & Irritation',
            'Eye Pain & Dryness',
            'Cataract / Refractive Check',
            'Watery Eyes & Discharge'
        ],
        symptomHint: 'e.g. Blurred distance vision, dry gritty eyes after screen use, or redness in one eye...',
        emergencyKeywords: ['sudden vision loss', 'chemical in eye', 'eye injury', 'flashes of light', 'curtain over vision', 'severe eye pain with nausea'],
        urgentKeywords: ['eye pain', 'light sensitivity', 'pus discharge', 'double vision', 'swollen eyelid'],
        selfCareGuidance: 'Do not rub your eyes, remove contact lenses if irritated, and avoid using leftover or steroid eye drops without an ophthalmologist examination.',
        emergencyWarning: 'Seek immediate emergency eye care for sudden vision loss, chemical splashes, penetrating eye trauma, sudden flashes/floaters, or severe eye pain with headache/nausea.',
        prescriptionSchema: {
            diagnosisLabel: 'Ophthalmic Diagnosis',
            sections: [
                { key: 'eyeDropsAndTopicals', label: 'Eye Drops / Ointments', placeholder: 'e.g. Lubricating drops, antibiotic drops (specify OD / OS / OU)...', multiline: true },
                { key: 'investigations', label: 'Vision & Eye Investigations', placeholder: 'e.g. Visual Acuity, IOP (Tonometry), Slit-Lamp Exam, OCT, Refraction...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'GASTRO',
        name: 'Gastroenterology',
        aliases: ['gastroenterology', 'gastroenterologist', 'hepatology', 'digestive', 'stomach', 'liver'],
        triageCategories: [
            'Abdominal Pain',
            'Acidity & Reflux',
            'Bloating & Indigestion',
            'Liver & Gallbladder Symptoms',
            'Bowel Habit Changes'
        ],
        symptomHint: 'e.g. Burning sensation after meals, upper abdominal discomfort, or persistent bloating...',
        emergencyKeywords: ['vomiting blood', 'black tarry stools', 'blood in stool', 'severe rigid abdomen', 'yellow eyes with confusion', 'unable to keep fluids down'],
        urgentKeywords: ['jaundice', 'persistent vomiting', 'severe abdominal pain', 'unexplained weight loss', 'dehydration'],
        selfCareGuidance: 'Eat light, bland, non-spicy meals, stay hydrated with water or oral rehydration fluids, and avoid NSAID painkillers or alcohol until evaluated.',
        emergencyWarning: 'Seek immediate emergency care for vomiting blood, black/bloody stools, severe unrelenting abdominal pain, high fever with yellowing of eyes/skin, or severe dehydration.',
        prescriptionSchema: {
            diagnosisLabel: 'Gastroenterology Diagnosis',
            sections: [
                { key: 'investigations', label: 'Lab Tests & Endoscopy / Imaging', placeholder: 'e.g. Ultrasound Abdomen, LFT, H. pylori test, Upper GI Endoscopy...', multiline: true },
                { key: 'dietInstructions', label: 'Dietary & Lifestyle Advice', placeholder: 'e.g. Small frequent meals, avoid spicy/fatty food, elevate head end...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'ONCO',
        name: 'Oncology',
        aliases: ['oncology', 'oncologist', 'medical oncology', 'surgical oncology', 'radiation oncology', 'cancer care'],
        triageCategories: [
            'Unexplained Lump or Swelling',
            'Persistent Fatigue or Weight Loss',
            'Cancer Screening & Second Opinion',
            'Post-Treatment Follow-up',
            'Biopsy / Pathology Report Review'
        ],
        symptomHint: 'e.g. Painless persistent lump, oncology second opinion, or post-treatment symptom follow-up...',
        emergencyKeywords: ['fever during chemotherapy', 'neutropenic fever', 'severe shortness of breath', 'uncontrolled bleeding', 'sudden leg weakness', 'confusion'],
        urgentKeywords: ['fever', 'severe nausea', 'persistent pain', 'new lump', 'unexplained bleeding'],
        selfCareGuidance: 'Keep all prior pathology, biopsy, imaging (CT/PET/MRI), and treatment summaries organized for your oncology consultation.',
        emergencyWarning: 'Seek immediate emergency care if you are undergoing cancer treatment and develop fever (>=100.4°F / 38°C), chills, severe shortness of breath, bleeding, or confusion.',
        prescriptionSchema: {
            diagnosisLabel: 'Oncology Clinical Assessment',
            sections: [
                { key: 'investigations', label: 'Staging, Lab & Imaging Workup', placeholder: 'e.g. CBC with Differential, Tumor Markers, CT/PET-CT, Biopsy review...', multiline: true },
                { key: 'supportiveCare', label: 'Supportive Care & Monitoring Instructions', placeholder: 'e.g. Infection precautions, hydration, antiemetic/pain monitoring...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'PSYCH',
        name: 'Psychiatry',
        aliases: ['psychiatry', 'psychiatrist', 'mental health', 'behavioral sciences', 'psychology'],
        triageCategories: [
            'Anxiety & Stress',
            'Sleep Disorders & Insomnia',
            'Persistent Low Mood',
            'Focus & Behavioral Concerns',
            'Counseling & Medication Review'
        ],
        symptomHint: 'e.g. Difficulty falling asleep for weeks, frequent anxiety, or persistent low mood...',
        emergencyKeywords: ['suicidal', 'self harm', 'hurt myself', 'harm others', 'hallucinations', 'severe panic unable to breathe'],
        urgentKeywords: ['severe insomnia', 'panic attacks', 'acute distress', 'medication side effects'],
        selfCareGuidance: 'Reach out to a trusted family member or friend, maintain a steady sleep routine, avoid alcohol or abrupt changes to existing psychiatric medicines without medical supervision.',
        emergencyWarning: 'EMERGENCY: If you or someone you know has thoughts of self-harm or suicide, please contact local emergency services or a crisis helpline immediately — confidential help is available 24/7.',
        prescriptionSchema: {
            diagnosisLabel: 'Psychiatric Assessment',
            sections: [
                { key: 'therapyPlan', label: 'Psychotherapy / Counseling Plan', placeholder: 'e.g. CBT sessions, sleep hygiene therapy, stress management plan...', multiline: true },
                { key: 'monitoringInstructions', label: 'Monitoring & Safety Instructions', placeholder: 'e.g. Do not stop medication abruptly; monitor sleep/mood; emergency contact...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'URO',
        name: 'Urology',
        aliases: ['urology', 'urologist', 'renal sciences', 'kidney', 'urinary'],
        triageCategories: [
            'Urinary Pain or Burning',
            'Frequent Urination',
            'Kidney Stone Symptoms',
            'Lower Abdominal / Flank Pain',
            'Prostate / Urological Review'
        ],
        symptomHint: 'e.g. Burning sensation during urination, side/flank pain, or frequent nighttime urination...',
        emergencyKeywords: ['unable to pass urine', 'acute urinary retention', 'severe testicular pain', 'heavy blood in urine', 'flank pain with high fever'],
        urgentKeywords: ['blood in urine', 'fever with burning urine', 'severe flank pain', 'vomiting with kidney pain'],
        selfCareGuidance: 'Maintain adequate water intake unless fluid-restricted by a physician, and bring any recent ultrasound or urine test reports to your appointment.',
        emergencyWarning: 'Seek immediate emergency care if you are completely unable to urinate, have sudden severe scrotal/testicular pain, or have flank pain accompanied by high fever and chills.',
        prescriptionSchema: {
            diagnosisLabel: 'Urological Diagnosis',
            sections: [
                { key: 'investigations', label: 'Urological Investigations', placeholder: 'e.g. Urine Routine & Culture, Ultrasound KUB, Serum Creatinine, PSA...', multiline: true },
                { key: 'careInstructions', label: 'Hydration & Care Instructions', placeholder: 'e.g. Daily fluid intake target, dietary stone precautions...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'PULMO',
        name: 'Pulmonology',
        aliases: ['pulmonology', 'pulmonologist', 'respiratory medicine', 'chest', 'lungs', 'asthma'],
        triageCategories: [
            'Persistent Cough',
            'Shortness of Breath',
            'Wheezing & Asthma',
            'Chest Tightness',
            'Sleep Apnea & Snoring'
        ],
        symptomHint: 'e.g. Cough lasting over 2 weeks, wheezing at night, or breathlessness on walking...',
        emergencyKeywords: ['severe shortness of breath', 'cannot speak full sentences', 'blue lips', 'coughing up blood', 'low oxygen', 'spo2 below 90', 'chest pain with breathlessness'],
        urgentKeywords: ['wheezing', 'asthma flare', 'fever with cough', 'shortness of breath', 'chest tightness'],
        selfCareGuidance: 'Avoid smoke, dust, and known triggers, sit upright if slightly breathless, monitor oxygen saturation (SpO2) if an oximeter is available, and bring any inhalers you use.',
        emergencyWarning: 'EMERGENCY: Seek immediate emergency care for severe difficulty breathing, inability to speak in full sentences, bluish lips/nails, coughing up blood, or SpO2 dropping below 92%.',
        prescriptionSchema: {
            diagnosisLabel: 'Pulmonary Diagnosis',
            sections: [
                { key: 'investigations', label: 'Pulmonary Investigations', placeholder: 'e.g. Chest X-Ray, Spirometry / PFT, Sputum Culture, HRCT Chest, SpO2...', multiline: true },
                { key: 'inhalerAndMonitoring', label: 'Inhaler Technique & Monitoring Instructions', placeholder: 'e.g. Spacer use, rinse mouth after steroid inhaler, peak flow/SpO2 log...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'ENDO',
        name: 'Endocrinology',
        aliases: ['endocrinology', 'endocrinologist', 'diabetes', 'diabetology', 'thyroid', 'metabolism'],
        triageCategories: [
            'Diabetes & Blood Sugar',
            'Thyroid Symptoms',
            'Hormonal Imbalance',
            'Weight & Metabolism Concerns',
            'Fatigue & Vitamin Deficiency'
        ],
        symptomHint: 'e.g. Fluctuating blood glucose levels, unexplained weight changes, or persistent tiredness...',
        emergencyKeywords: ['very low blood sugar', 'blood sugar below 60', 'confusion', 'fruity breath', 'rapid breathing with high sugar', 'blood sugar above 400', 'fainting'],
        urgentKeywords: ['high blood sugar', 'dizziness', 'palpitations', 'excessive thirst', 'vomiting with diabetes'],
        selfCareGuidance: 'Keep a log of fasting and post-meal blood sugar readings (if diabetic) and bring your latest HbA1c, TSH, and medication list to the consultation.',
        emergencyWarning: 'Seek immediate emergency care for severe hypoglycemia (confusion, shakiness, fainting) or very high blood sugar with nausea, vomiting, abdominal pain, or rapid breathing.',
        prescriptionSchema: {
            diagnosisLabel: 'Endocrine Diagnosis',
            sections: [
                { key: 'labTests', label: 'Hormone & Metabolic Lab Tests', placeholder: 'e.g. HbA1c, Fasting/PP Glucose, TSH/Free T3/T4, Vitamin D, Lipid Profile...', multiline: true },
                { key: 'monitoringInstructions', label: 'Glucose / Diet & Monitoring Plan', placeholder: 'e.g. SMBG schedule, meal plan, hypoglycemia action instructions...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    },
    {
        code: 'PHYSIO',
        name: 'Physiotherapy',
        aliases: ['physiotherapy', 'physiotherapist', 'physical therapy', 'rehabilitation', 'rehab'],
        triageCategories: [
            'Back & Neck Stiffness',
            'Joint Mobility & Rehab',
            'Post-Surgery Rehabilitation',
            'Sports Injury Recovery',
            'Posture & Muscle Strain'
        ],
        symptomHint: 'e.g. Stiff neck from desk posture, knee stiffness after surgery, or shoulder strain...',
        emergencyKeywords: ['sudden limb weakness', 'loss of bladder', 'loss of bowel', 'suspected fracture', 'severe chest pain during exercise'],
        urgentKeywords: ['sharp radiating pain', 'numbness', 'acute joint swelling', 'unable to walk'],
        selfCareGuidance: 'Avoid movements that trigger sharp pain, apply gentle ice or heat as tolerated, and bring any orthopedic X-ray/MRI or post-operative notes.',
        emergencyWarning: 'Seek immediate medical care if pain is accompanied by sudden numbness/weakness in limbs, loss of bowel/bladder control, or suspected bone fracture.',
        prescriptionSchema: {
            diagnosisLabel: 'Rehabilitation Assessment',
            sections: [
                { key: 'physiotherapyRecommendations', label: 'Physiotherapy & Exercise Protocol', placeholder: 'e.g. Stretching, strengthening sets, modality (TENS/IFT/Ultrasound), frequency...', multiline: true },
                { key: 'treatmentInstructions', label: 'Home Precautions & Ergonomics', placeholder: 'e.g. Posture correction, activity limits, ice/heat application schedule...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    }
];

function buildGenericConfigForSpecialty(specialtyName) {
    const cleanName = String(specialtyName || 'General Medicine').trim() || 'General Medicine';
    return {
        code: cleanName.toUpperCase().replace(/[^A-Z0-9]+/g, '_').slice(0, 14) || 'MEDICAL',
        name: cleanName,
        aliases: [cleanName.toLowerCase()],
        triageCategories: [
            `${cleanName} Consultation`,
            'Symptom Evaluation',
            'Pain or Discomfort',
            'Diagnostic & Report Review',
            'Follow-up Care'
        ],
        symptomHint: `e.g. Describe your symptoms, when they started, and any relevant medical history for ${cleanName}...`,
        emergencyKeywords: ['chest pain', 'difficulty breathing', 'unconscious', 'seizure', 'uncontrolled bleeding', 'slurred speech', 'sudden weakness'],
        urgentKeywords: ['high fever', 'severe pain', 'persistent vomiting', 'fainting', 'swelling'],
        selfCareGuidance: `Note when your symptoms began, what worsens or relieves them, and keep any prior medical reports ready for your ${cleanName} specialist.`,
        emergencyWarning: 'Seek immediate emergency medical care if you experience chest pain, severe difficulty breathing, fainting, sudden weakness/numbness, seizures, or uncontrolled bleeding.',
        prescriptionSchema: {
            diagnosisLabel: 'Clinical Diagnosis',
            sections: [
                { key: 'symptoms', label: 'Clinical Findings / Symptoms', placeholder: 'e.g. Presenting symptoms, clinical observations, vitals...', multiline: true },
                { key: 'investigations', label: 'Investigations / Lab Tests', placeholder: 'e.g. Recommended diagnostic tests or imaging...', multiline: true },
                { key: 'treatmentInstructions', label: 'Treatment & Care Instructions', placeholder: 'e.g. Specific medical care, lifestyle advice, precautions...', multiline: true }
            ],
            showFollowUpDate: true,
            medicationFields: ['name', 'dosage', 'frequency', 'duration', 'instructions']
        }
    };
}

function getSpecialtyClinicalConfig(specialtyName) {
    const clean = String(specialtyName || '').trim();
    if (!clean || clean.toLowerCase() === 'all' || clean.toLowerCase() === 'all specialties') {
        return getSpecialtyClinicalConfig('General Medicine');
    }
    const lower = clean.toLowerCase();
    // 1. Exact match on name, code, or alias first (prevents 'ent' matching substring of 'dentistry')
    for (const cfg of SPECIALTY_CONFIGS) {
        if (
            cfg.name.toLowerCase() === lower ||
            cfg.code.toLowerCase() === lower ||
            cfg.aliases.includes(lower)
        ) {
            return cfg;
        }
    }
    // 2. Partial/substring match for longer compound specialty names (e.g. 'Interventional Cardiology')
    for (const cfg of SPECIALTY_CONFIGS) {
        if (cfg.aliases.some(a => a.length >= 4 && lower.includes(a))) {
            return cfg;
        }
    }
    return buildGenericConfigForSpecialty(clean);
}

// Universal cross-specialty emergency indicators
const UNIVERSAL_EMERGENCY_KEYWORDS = [
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
    'throat swelling'
];

function analyzeSymptomsForSpecialty({
    specialty,
    category,
    symptoms,
    severity = 'Moderate',
    duration = '2-3 days'
}) {
    const config = getSpecialtyClinicalConfig(specialty);
    const text = String(symptoms || '').trim();
    const lower = `${text} ${category || ''}`.toLowerCase();
    const sevLower = String(severity || 'Moderate').trim().toLowerCase();

    const matchedEmergency = [
        ...UNIVERSAL_EMERGENCY_KEYWORDS,
        ...(config.emergencyKeywords || [])
    ].find(kw => lower.includes(kw));

    const matchedUrgent = (config.urgentKeywords || []).find(kw => lower.includes(kw));

    let urgencyLevel = 'Routine';
    let urgency = 'Routine Consultation Suggested';
    let isEmergency = false;
    let summary;

    if (matchedEmergency || sevLower === 'severe') {
        isEmergency = Boolean(matchedEmergency);
        urgencyLevel = isEmergency ? 'Emergency' : 'Urgent';
        urgency = isEmergency
            ? 'Emergency Evaluation Recommended Immediately'
            : 'Urgent Specialist Care Recommended (< 24 hrs)';
        summary = isEmergency
            ? `Your reported symptoms in ${config.name} (${category || 'General'}) include potential warning signs that require prompt in-person medical evaluation.`
            : `Severe ${config.name.toLowerCase()} symptoms (${category || 'reported concern'}) lasting ${duration} warrant a prompt specialist consultation within 24 hours.`;
    } else if (sevLower === 'moderate' || matchedUrgent) {
        urgencyLevel = 'Soon';
        urgency = 'Specialist Consultation Recommended (24–72 hrs)';
        summary = `Your symptoms under ${config.name}${category ? ` (${category})` : ''} should be evaluated by a qualified ${config.name} specialist within 24–72 hours for a proper examination.`;
    } else {
        urgencyLevel = 'Routine';
        urgency = 'Routine Evaluation Suggested';
        summary = `Mild symptoms under ${config.name}${category ? ` (${category})` : ''} can typically be discussed at a routine specialist appointment. Monitor for any worsening signs.`;
    }

    return {
        specialty: config.name,
        specialtyCode: config.code,
        category: category || config.triageCategories[0],
        severity,
        duration,
        urgencyLevel,
        urgency,
        isEmergency,
        disclaimer: 'Informational triage guidance only — this is NOT a medical diagnosis. Please consult a qualified doctor for clinical evaluation and treatment.',
        clinicalSummary: summary,
        recommendedSpecialty: config.name,
        selfCareGuidance: config.selfCareGuidance,
        emergencyWarning: config.emergencyWarning,
        triageCategories: config.triageCategories,
        analyzedAt: new Date().toISOString()
    };
}

module.exports = {
    SPECIALTY_CONFIGS,
    getSpecialtyClinicalConfig,
    analyzeSymptomsForSpecialty
};
