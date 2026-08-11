# DentaGuru — Firebase App Distribution & Build Pipeline Guide

This guide documents the setup and automated build/distribution process for deploying DentaGuru Android & iOS test builds to internal testers using **Firebase App Distribution**.

---

## 🏗️ Architecture Overview

The DentaGuru mobile application utilizes Firebase for continuous quality and distribution:
* **Firebase Analytics**: Tracks user engagements (App Open, Login, Registration, OTP, Doctor Selection, Appointments, Consultations).
* **Firebase Crashlytics**: Captures fatal crashes and non-fatal errors in real-time.
* **Firebase App Distribution**: Distributes pre-release APKs/IPAs to internal QA teams and testers.
* **CI/CD Build Pipeline**: Automated via GitHub Actions workflow (`.github/workflows/firebase_app_distribution.yml`).

---

## 🔑 Required Secrets & Environment Variables

To run the pipeline without exposing credentials in code, set the following secrets in your **GitHub Repository Secrets** (`Settings > Secrets and variables > Actions`):

| Secret Name | Description | Example |
| :--- | :--- | :--- |
| `FIREBASE_APP_ID_ANDROID` | Firebase Android App ID from Firebase Console | `1:1234567890:android:a1b2c3d4e5` |
| `FIREBASE_APP_ID_IOS` | Firebase iOS App ID from Firebase Console | `1:1234567890:ios:f6g7h8i9j0` |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | Contents of Firebase Service Account JSON file | `{ "type": "service_account", ... }` |
| `FIREBASE_TOKEN` | (Alternative) Token generated via `firebase login:ci` | `1//0gXYZ...` |

---

## 🤖 Automated Distribution (GitHub Actions)

When code is pushed to `main` / `master` or manually triggered via the **Actions** tab:
1. GitHub Actions checks out the codebase.
2. Sets up Java 17 and Flutter SDK 3.22.x.
3. Compiles the release APK (`flutter build apk --release`).
4. Invokes Firebase App Distribution to upload the APK and notify tester groups (`internal-testers`).

---

## 💻 Local CLI Build & Distribution

To build and distribute a test release directly from your local machine:

1. Install Firebase CLI (if not already installed):
   ```bash
   npm install -g firebase-tools
   firebase login
   ```

2. Execute the PowerShell distribution script:
   ```powershell
   .\scripts\distribute_app.ps1 -AppId "1:1234567890:android:abcdef" -TesterGroup "internal-testers" -ReleaseNotes "QA Test Release v1.0.2"
   ```

---

## 🔒 Privacy & Compliance
* **No PII/PHI Transmitted**: Firebase Analytics and Crashlytics are configured to track operational performance and crash metrics without logging sensitive patient health data.
