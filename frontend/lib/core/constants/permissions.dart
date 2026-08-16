class AppPermissions {
  // 1. Patient Management
  static const String patientView = 'PATIENT_VIEW';
  static const String patientAdd = 'PATIENT_ADD';
  static const String patientEdit = 'PATIENT_EDIT';

  // 2. Dentist Management
  static const String dentistView = 'DENTIST_VIEW';
  static const String dentistCreate = 'DENTIST_CREATE';
  static const String dentistEdit = 'DENTIST_EDIT';

  // 3. Assignment Management
  static const String assignmentView = 'ASSIGNMENT_VIEW';
  static const String assignmentCreate = 'ASSIGNMENT_CREATE';

  // 4. Appointment Management
  static const String appointmentView = 'APPOINTMENT_VIEW';
  static const String appointmentManage = 'APPOINTMENT_MANAGE';

  // 5. Problem Request Management
  static const String problemView = 'PROBLEM_VIEW';
  static const String problemUpdate = 'PROBLEM_UPDATE';

  // 6. Reports & Monitoring
  static const String reportView = 'REPORT_VIEW';

  /// All permission groups structured for UI checkbox rendering
  static const List<PermissionGroup> groups = [
    PermissionGroup(
      title: 'Patient Management',
      icon: '👥',
      description: 'Access patient records, registrations, and updates',
      permissions: [
        PermissionItem(key: patientView, label: 'View Patients List & Details', isDefault: true),
        PermissionItem(key: patientAdd, label: 'Register New Patients'),
        PermissionItem(key: patientEdit, label: 'Edit Patient Profiles & Status'),
      ],
    ),
    PermissionGroup(
      title: 'Dentist Management',
      icon: '🩺',
      description: 'Access dentist profiles, clinics, and credentials',
      permissions: [
        PermissionItem(key: dentistView, label: 'View Dentists & Availability', isDefault: true),
        PermissionItem(key: dentistCreate, label: 'Register / Add New Dentists'),
        PermissionItem(key: dentistEdit, label: 'Edit Dentist Info & Verify Accounts'),
      ],
    ),
    PermissionGroup(
      title: 'Doctor Assignment & Referrals',
      icon: '🤝',
      description: 'Coordinate patient inquiries with local dental specialists',
      permissions: [
        PermissionItem(key: assignmentView, label: 'View Patient Requests & Nearby Doctors', isDefault: true),
        PermissionItem(key: assignmentCreate, label: 'Assign Patients to Dentists (WhatsApp / In-App)', isDefault: true),
      ],
    ),
    PermissionGroup(
      title: 'Appointment Management',
      icon: '📅',
      description: 'Oversee and reschedule clinic consultations',
      permissions: [
        PermissionItem(key: appointmentView, label: 'View All Appointments & Schedules', isDefault: true),
        PermissionItem(key: appointmentManage, label: 'Reschedule, Accept, or Cancel Appointments'),
      ],
    ),
    PermissionGroup(
      title: 'Problem & Inquiry Pool',
      icon: '💬',
      description: 'Track incoming dental symptoms and consultation requests',
      permissions: [
        PermissionItem(key: problemView, label: 'View Patient Problem Requests', isDefault: true),
        PermissionItem(key: problemUpdate, label: 'Update Problem Status & Mark Reviewed'),
      ],
    ),
    PermissionGroup(
      title: 'Reports & Analytics',
      icon: '📊',
      description: 'View platform volume, doctor referral metrics, and statistics',
      permissions: [
        PermissionItem(key: reportView, label: 'View Dashboard Statistics & Metrics', isDefault: true),
      ],
    ),
  ];

  /// Get list of default permissions recommended for a standard Sub-Admin
  static List<String> get defaultPermissions {
    final List<String> defaults = [];
    for (final group in groups) {
      for (final perm in group.permissions) {
        if (perm.isDefault) {
          defaults.add(perm.key);
        }
      }
    }
    return defaults;
  }

  /// Human-readable label for a given permission key
  static String getLabel(String key) {
    final k = key.trim().toUpperCase();
    for (final group in groups) {
      for (final perm in group.permissions) {
        if (perm.key.toUpperCase() == k) {
          return perm.label;
        }
      }
    }
    return key;
  }
}

class PermissionGroup {
  final String title;
  final String icon;
  final String description;
  final List<PermissionItem> permissions;

  const PermissionGroup({
    required this.title,
    required this.icon,
    required this.description,
    required this.permissions,
  });
}

class PermissionItem {
  final String key;
  final String label;
  final bool isDefault;

  const PermissionItem({
    required this.key,
    required this.label,
    this.isDefault = false,
  });
}
