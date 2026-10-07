class DentalPrescriptionTemplate {
  final String name;
  final String category;
  final String defaultDosage;
  final String defaultFrequency;
  final String defaultDuration;
  final String defaultInstructions;

  const DentalPrescriptionTemplate({
    required this.name,
    required this.category,
    required this.defaultDosage,
    required this.defaultFrequency,
    required this.defaultDuration,
    required this.defaultInstructions,
  });
}

const List<String> dentalDiagnosisPresets = [
  'Dental Evaluation',
  'Acute Pulpitis / Severe Toothache',
  'Dental Abscess / Periapical Infection',
  'Post-Extraction Surgical Care',
  'Pericoronitis (Wisdom Tooth Pain)',
  'Gingivitis & Periodontal Infection',
  'Root Canal Therapy (RCT) Recovery',
  'Aphthous Stomatitis (Mouth Ulcers)',
  'Dental Implant Placement Care',
  'Crown & Bridge Preparation Sensitivity',
  'Custom Diagnosis...',
];

const List<DentalPrescriptionTemplate> dentalPrescriptionTemplates = [
  // 1. Antibiotics
  DentalPrescriptionTemplate(
    name: 'Amoxicillin 500mg',
    category: 'Antibiotic',
    defaultDosage: '1 Capsule',
    defaultFrequency: 'Every 8 Hours (1-1-1)',
    defaultDuration: '5 Days',
    defaultInstructions: 'Take after meals with plenty of water. Complete the full antibiotic course.',
  ),
  DentalPrescriptionTemplate(
    name: 'Augmentin 625mg (Amox + Clav)',
    category: 'Antibiotic',
    defaultDosage: '1 Tablet',
    defaultFrequency: 'Twice Daily (1-0-1)',
    defaultDuration: '5 Days',
    defaultInstructions: 'Take with or immediately after meals to avoid gastric discomfort.',
  ),
  DentalPrescriptionTemplate(
    name: 'Metronidazole 400mg (Flagyl)',
    category: 'Antibiotic',
    defaultDosage: '1 Tablet',
    defaultFrequency: 'Thrice Daily (1-1-1)',
    defaultDuration: '5 Days',
    defaultInstructions: 'For anaerobic/gum infection. Strictly avoid alcohol during medication course.',
  ),
  DentalPrescriptionTemplate(
    name: 'Azithromycin 500mg',
    category: 'Antibiotic',
    defaultDosage: '1 Tablet',
    defaultFrequency: 'Once Daily (1-0-0)',
    defaultDuration: '3 Days',
    defaultInstructions: 'Take 1 hour before or 2 hours after meals (Penicillin-allergic alternative).',
  ),
  DentalPrescriptionTemplate(
    name: 'Clindamycin 300mg',
    category: 'Antibiotic',
    defaultDosage: '1 Capsule',
    defaultFrequency: 'Every 6 Hours (1-1-1-1)',
    defaultDuration: '5 Days',
    defaultInstructions: 'Take with a full glass of water; for refractory bone/deep tissue infections.',
  ),
  DentalPrescriptionTemplate(
    name: 'Cefixime 200mg',
    category: 'Antibiotic',
    defaultDosage: '1 Tablet',
    defaultFrequency: 'Twice Daily (1-0-1)',
    defaultDuration: '5 Days',
    defaultInstructions: 'Take after food for acute odontogenic infections.',
  ),

  // 2. Analgesics & Anti-Inflammatories (Pain Relief)
  DentalPrescriptionTemplate(
    name: 'Zerodol-SP (Aceclo + Para + Serratio)',
    category: 'Pain & Swelling',
    defaultDosage: '1 Tablet',
    defaultFrequency: 'Twice Daily (1-0-1)',
    defaultDuration: '3 Days',
    defaultInstructions: 'Take strictly after food for pain, inflammation and swelling reduction.',
  ),
  DentalPrescriptionTemplate(
    name: 'Combiflam (Ibuprofen + Paracetamol)',
    category: 'Pain Relief',
    defaultDosage: '1 Tablet',
    defaultFrequency: 'Thrice Daily (1-1-1)',
    defaultDuration: '3 Days',
    defaultInstructions: 'Take strictly after meals for acute toothache and post-procedure pain.',
  ),
  DentalPrescriptionTemplate(
    name: 'Ketorol-DT 10mg (Dispersible)',
    category: 'Severe Pain',
    defaultDosage: '1 Dispersible Tablet',
    defaultFrequency: 'Twice Daily (1-0-1)',
    defaultDuration: '3 Days',
    defaultInstructions: 'Disperse tablet in 15ml water; take after food for acute severe pain.',
  ),
  DentalPrescriptionTemplate(
    name: 'Dolo 650mg (Paracetamol)',
    category: 'Mild Pain / Fever',
    defaultDosage: '1 Tablet',
    defaultFrequency: 'Every 6-8 Hours as needed',
    defaultDuration: '3 Days',
    defaultInstructions: 'Safe mild analgesic; take after food if fever or mild pain occurs.',
  ),
  DentalPrescriptionTemplate(
    name: 'Ultracet (Tramadol + Paracetamol)',
    category: 'Severe Post-Op Pain',
    defaultDosage: '1 Tablet',
    defaultFrequency: 'As needed (Max 2 daily)',
    defaultDuration: '2 Days',
    defaultInstructions: 'For severe surgical pain. May cause mild drowsiness. Take after meals.',
  ),

  // 3. Mouthwashes & Oral Antiseptics
  DentalPrescriptionTemplate(
    name: 'Hexidine 0.2% (Chlorhexidine Mouthwash)',
    category: 'Oral Antiseptic',
    defaultDosage: '10ml undiluted',
    defaultFrequency: 'Twice Daily (1-0-1)',
    defaultDuration: '14 Days',
    defaultInstructions: 'Swish for 60 seconds after brushing. Do not rinse, eat or drink for 30 minutes.',
  ),
  DentalPrescriptionTemplate(
    name: 'Betadine 2% Gargle (Povidone Iodine)',
    category: 'Oral Antiseptic',
    defaultDosage: 'Dilute 1:1 with warm water',
    defaultFrequency: 'Thrice Daily (1-1-1)',
    defaultDuration: '7 Days',
    defaultInstructions: 'Gargle for 30 seconds and spit out. Do not swallow.',
  ),

  // 4. Gastric Protective Agents (PPI)
  DentalPrescriptionTemplate(
    name: 'Pan-40 (Pantoprazole 40mg)',
    category: 'Antacid / PPI',
    defaultDosage: '1 Tablet',
    defaultFrequency: 'Once Daily (1-0-0)',
    defaultDuration: '5 Days',
    defaultInstructions: 'Take 30 minutes before breakfast on empty stomach to protect gastric lining.',
  ),
  DentalPrescriptionTemplate(
    name: 'Razo-D (Rabeprazole + Domperidone)',
    category: 'Antacid / PPI',
    defaultDosage: '1 Capsule',
    defaultFrequency: 'Once Daily (1-0-0)',
    defaultDuration: '5 Days',
    defaultInstructions: 'Take on empty stomach in the morning 30 minutes before food.',
  ),

  // 5. Topical Gels & Ulcer Pastes
  DentalPrescriptionTemplate(
    name: 'Mucopain Oral Gel (Benzocaine 20%)',
    category: 'Topical Anesthetic',
    defaultDosage: 'Small pea-sized dab',
    defaultFrequency: '3-4 Times Daily',
    defaultDuration: '5 Days',
    defaultInstructions: 'Apply gently to painful ulcer/wound area 10 minutes before meals.',
  ),
  DentalPrescriptionTemplate(
    name: 'Kenacort 0.1% Oral Paste (Triamcinolone)',
    category: 'Anti-Ulcer Paste',
    defaultDosage: 'Thin layer film',
    defaultFrequency: 'At bedtime (0-0-1)',
    defaultDuration: '5 Days',
    defaultInstructions: 'Press small dab onto aphthous ulcer without rubbing until smooth film forms.',
  ),

  // 6. Bleeding Control
  DentalPrescriptionTemplate(
    name: 'Pause 500mg (Tranexamic Acid)',
    category: 'Hemostatic',
    defaultDosage: '1 Tablet',
    defaultFrequency: 'Thrice Daily (1-1-1)',
    defaultDuration: '2 Days',
    defaultInstructions: 'Take after meals for post-extraction bleeding control if prescribed.',
  ),
];

DentalPrescriptionTemplate? findDentalMedicationTemplate(String name) {
  final clean = name.trim().toLowerCase();
  for (final t in dentalPrescriptionTemplates) {
    if (t.name.toLowerCase().contains(clean) || clean.contains(t.name.toLowerCase())) {
      return t;
    }
  }
  return null;
}
