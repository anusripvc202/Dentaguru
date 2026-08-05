# Workspace Rules for DentaGuru

1. **No Dummy Fallback Data**: Never hardcode dummy arrays or fallback sample records (`Dr. Elena Rodriguez`, `1,284 patients`, `₹24,85,200`) in controllers or UI components. Return clean empty states when database tables are uninitialized.
2. **End-to-End Real-Time Persistence**: All actions (registering patients/doctors/clinics, assigning specialists, issuing e-prescriptions, booking appointments) MUST be saved immediately to Supabase database tables (`users`, `appointments`, `medical_records`, `clinics`, `dentists`) AND local state services.
3. **Auto-Sync on Application Launch**: Always trigger automatic sync calls (`syncAppointmentsFromApi()`, `fetchMedicalRecords()`, `fetchDentists()`, `fetchClinics()`) when state services initialize so browser refreshes or app restarts maintain 100% data fidelity with Supabase.
