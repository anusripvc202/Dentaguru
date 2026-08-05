# DentaGuru Mobile & Web Application Documentation
**Comprehensive Technical & Operating Manual**
*Version 2.0 | Google DeepMind Agentic Systems Architecture*

---

## 1. Executive Summary & System Overview

**DentaGuru** is an end-to-end, multi-portal digital dental healthcare ecosystem built to streamline patient consultations, clinic management, specialist triage, and real-time electronic health records (E-Prescriptions).

### Core Technological Stack
- **Frontend App**: Cross-platform Flutter Web & Mobile application (`lib/main.dart`).
- **Backend API**: Node.js & Express.js RESTful API Server operating on Port `5000`.
- **Database Layer**: Supabase Cloud PostgreSQL Relational Database (`fommrwxpqzkcktweosgp.supabase.co`).
- **State Management**: `PatientProblemService` singleton service with auto-syncing reactive listeners and local storage fallback.

---

## 2. Multi-Role Ecosystem & User Portals

DentaGuru provides tailored workspaces for 4 distinct user roles:

| Role | Target Route | Primary Responsibilities |
| :--- | :--- | :--- |
| **Patient** | `/patient` | Submit oral health symptoms, view assigned specialists, track appointment status, access digital E-Prescriptions in Health Locker. |
| **Dentist** | `/dentist` | Receive forwarded symptom requests from Admin, accept & schedule appointments, issue live digital E-Prescriptions, log 3D tooth conditions. |
| **Clinic Manager** | `/clinic` | Manage clinic branch profile, configure procedure fee rate cards (Consultation, Root Canal, Orthodontics), monitor daily patient queue. |
| **Super Admin** | `/admin` | Triage incoming patient requests, assign specialists, register new doctors/clinics, remove users/doctors, monitor real-time practice revenue. |

---

## 3. End-to-End Workflows & Data Pipelines

### A. Patient Symptom Triage Pipeline
1. **Submission**: Patient fills in problem category, symptom description, and severity on `/patient`. Initial status: `Pending Admin Review`.
2. **Admin Triage**: Admin reviews the pending request on `/admin`, selects an available specialist, and clicks **`Send Doctor Recommendation`**. Status changes to `Pending Acceptance`.
3. **Doctor Acceptance**: The assigned Doctor receives the notification under **Admin Forwarded Symptoms** on `/dentist` and clicks **`Accept & Schedule`**. Status changes to `Accepted` (Green badge).
4. **Live Synchronization**: The appointment status updates live on the Patient's dashboard to `Confirmed`.

### B. Live E-Prescription Delivery Pipeline
1. Doctor opens `/dentist` → clicks **`Issue E-Prescription`**.
2. Doctor specifies medicine name, dosage, duration, and instructions.
3. System saves the record to Supabase `medical_records` table and updates local state.
4. Patient's Health Locker on `/patient` receives the digital prescription slip instantly.

### C. Rates & Time Slot Management
1. Doctor/Clinic can update consultation fees and next available slots from `/admin`, `/clinic`, or directly from the Doctor greeting banner on `/dentist`.
2. Procedure rate cards (General Consultation, Tooth Decay, Root Canal, Orthodontics) update live across all doctor cards.

---

## 4. Supabase Database Schema

DentaGuru uses 6 relational tables in Supabase PostgreSQL:

1. **`users`**:
   - `id` (UUID), `name`, `email`, `phone`, `role` (`Patient`, `Dentist`, `Admin`, `Clinic`), `password` (BCrypt hash), `created_at`.
2. **`dentists`**:
   - `id` (UUID), `user_id` (FK), `clinic_id` (FK), `speciality`, `license_number`, `availability_status`, `rating`, `reviews_count`.
3. **`clinics`**:
   - `id` (UUID), `user_id` (FK), `clinic_name`, `location`, `verified`, `pricing` (JSONB array of procedure rates).
4. **`appointments`**:
   - `id` (UUID), `patient_id` (FK), `dentist_id` (FK), `clinic_id` (FK), `date`, `time_slot`, `treatment`, `status` (`pending`, `confirmed`, `completed`).
5. **`medical_records`**:
   - `id` (UUID), `patient_id` (FK), `dentist_id` (FK), `diagnosis`, `prescriptions` (JSONB array), `notes` (JSONB metadata).
6. **`chat_messages`**:
   - `id` (UUID), `sender_id`, `receiver_id`, `message_text`, `created_at`.

---

## 5. API Endpoint Reference

- `POST /api/v1/auth/register`: Register new user (Patient, Dentist, Clinic, Admin).
- `POST /api/v1/auth/login`: Authenticate user and return JWT tokens + role routing.
- `GET /api/v1/appointments`: Fetch live appointments from Supabase.
- `POST /api/v1/appointments`: Create/book new appointment.
- `GET /api/v1/records`: Fetch medical records & E-Prescriptions for a patient.
- `POST /api/v1/records`: Issue new digital E-Prescription.
- `POST /api/v1/auth/reset-db`: Truncate all database tables for fresh testing.

---

## 6. Workspace Quality Rules

1. **No Dummy Fallback Data**: Zero hardcoded dummy sample arrays in UI or controllers. Clean empty states when uninitialized.
2. **End-to-End Real-Time Persistence**: All user actions are immediately saved to Supabase PostgreSQL database tables.
3. **Auto-Sync on Launch**: Automatic sync calls (`syncAppointmentsFromApi()`, `fetchMedicalRecords()`, `fetchDentists()`, `fetchClinics()`) maintain 100% data fidelity on page refreshes.
