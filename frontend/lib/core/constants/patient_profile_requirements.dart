/// Centralized, flexible configuration for Deferred Patient Profile Completion.
///
/// All 9 client-discussed patient profile fields are rendered and persisted
/// against the authenticated patient's existing account ID. Mandatory vs.
/// optional enforcement is controlled here so client confirmation changes
/// require only flipping a boolean flag without rewriting UI or service logic.
class PatientProfileRequirementsConfig {
  PatientProfileRequirementsConfig._();

  // Core mandatory fields currently active across staging & automated suites:
  static bool requireProfileImage = false;
  static bool requirePincode = false;
  static bool requireAge = false;
  static bool requireGender = true;

  // Flexible fields awaiting final client mandatory/optional sign-off:
  static bool requireFullName = false;
  static bool requireAddress = false;
  static bool requirePreferredLanguage = false;
  static bool requireBloodGroup = false;

  static const List<String> genderOptions = <String>[
    'Female',
    'Male',
    'Other',
  ];

  static const List<String> bloodGroupOptions = <String>[
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  static const List<String> supportedLanguages = <String>[
    'English',
    'Hindi',
    'Telugu',
    'Tamil',
    'Kannada',
    'Malayalam',
    'Marathi',
    'Bengali',
    'Gujarati',
    'Urdu',
  ];

  static void resetDefaults() {
    requireProfileImage = false;
    requirePincode = false;
    requireAge = false;
    requireGender = true;
    requireFullName = false;
    requireAddress = false;
    requirePreferredLanguage = false;
    requireBloodGroup = false;
  }

  /// Validates a 6-digit Indian PIN code.
  static bool isValidPincode(String raw) {
    final clean = raw.trim();
    return RegExp(r'^\d{6}$').hasMatch(clean);
  }

  /// Validates patient age within 1..120 years.
  static bool isValidAge(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty || !RegExp(r'^\d+$').hasMatch(clean)) return false;
    final parsed = int.tryParse(clean);
    return parsed != null && parsed >= 1 && parsed <= 120;
  }

  /// Returns true when an email string is an internal synthetic placeholder
  /// generated for mobile-only OTP accounts and should not be shown in UI.
  static bool isSyntheticInternalEmail(String? rawEmail) {
    final clean = (rawEmail ?? '').trim().toLowerCase();
    if (clean.isEmpty || clean == 'null') return true;
    return clean.endsWith('@dentaguru.internal') ||
        clean == 'patient@dentaguru.com' ||
        clean == 'doctor@dentaguru.com' ||
        (clean.startsWith('dentist_') && clean.endsWith('@dentaguru.com')) ||
        (clean.startsWith('user_') && clean.contains('@dentaguru.'));
  }

  /// Returns a clean user-facing email, or empty string if synthetic/unset.
  static String sanitizeDisplayEmail(String? rawEmail) {
    if (isSyntheticInternalEmail(rawEmail)) return '';
    return (rawEmail ?? '').trim();
  }
}
