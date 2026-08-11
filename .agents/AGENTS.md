# Workspace Rules for DentaGuru

1. **No Dummy Fallback Data**: Never hardcode dummy arrays or fallback sample records (`Dr. Elena Rodriguez`, `1,284 patients`, `₹24,85,200`) in controllers or UI components. Return clean empty states when database tables are uninitialized.
2. **End-to-End Real-Time Persistence**: All actions (registering patients/doctors/clinics, assigning specialists, issuing e-prescriptions, booking appointments) MUST be saved immediately to Supabase database tables (`users`, `appointments`, `medical_records`, `clinics`, `dentists`) AND local state services.
3. **Auto-Sync on Application Launch**: Always trigger automatic sync calls (`syncAppointmentsFromApi()`, `fetchMedicalRecords()`, `fetchDentists()`, `fetchClinics()`) when state services initialize so browser refreshes or app restarts maintain 100% data fidelity with Supabase.
4. **Strict Android PNG Asset Signatures**: All Android launcher icons in `android/app/src/main/res/mipmap-*/` MUST be valid `%PNG` binary files to prevent AAPT2 Gradle `assembleRelease` resource merger compilation failures.
5. **Responsive Layouts & RenderFlex Safety**: Always wrap horizontal flex text elements in `Flexible` or `Expanded` with `TextOverflow.ellipsis` to prevent `RenderFlex` overflow assertions on narrow mobile viewports or headless test runners.
6. **Widget Test ProviderScope Wrapping**: Always wrap root app widgets in `ProviderScope` within `widget_test.dart` to prevent Riverpod state initializer exceptions in automated CI pipelines.
7. **24/7 Supabase Cloud Auth Fallback & Cold-Start Resilience**: All authentication and data fetch calls in `ApiService` MUST use minimum 35-second timeouts to accommodate Render server cold starts, AND MUST include direct 24/7 Supabase Cloud (`Supabase.instance.client.auth`) fallback handling so login/registration never fails even if the Express server is sleeping.


