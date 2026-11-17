class AppPermissions {
  // 1. Patient Management
  static const String patientView = 'PATIENT_VIEW';
  static const String patientCreate = 'PATIENT_CREATE';
  static const String patientAdd = 'PATIENT_ADD'; // Alias for backward compatibility
  static const String patientEdit = 'PATIENT_EDIT';
  static const String patientDelete = 'PATIENT_DELETE';

  // 2. Doctor Management
  static const String dentistView = 'DENTIST_VIEW';
  static const String dentistVerify = 'DENTIST_VERIFY';
  static const String dentistManage = 'DENTIST_MANAGE';
  static const String dentistCreate = 'DENTIST_CREATE'; // Alias
  static const String dentistEdit = 'DENTIST_EDIT'; // Alias

  // 3. Patient Assignment
  static const String assignmentView = 'ASSIGNMENT_VIEW';
  static const String assignmentCreate = 'ASSIGNMENT_CREATE';
  static const String assignmentHistoryView = 'ASSIGNMENT_HISTORY_VIEW';

  // 4. Clinic Management
  static const String clinicView = 'CLINIC_VIEW';
  static const String clinicManage = 'CLINIC_MANAGE';

  // 5. Referral Management
  static const String referralView = 'REFERRAL_VIEW';
  static const String referralManage = 'REFERRAL_MANAGE';

  // 6. Appointment Management
  static const String appointmentView = 'APPOINTMENT_VIEW';
  static const String appointmentManage = 'APPOINTMENT_MANAGE';

  // 7. Problem Request Management
  static const String problemView = 'PROBLEM_VIEW';
  static const String problemUpdate = 'PROBLEM_UPDATE';

  // 8. Reports & Analytics
  static const String reportView = 'REPORT_VIEW';

  // 9. System Administration (Main Admin only)
  static const String adminSubAdminManage = 'ADMIN_SUBADMIN_MANAGE';
  static const String adminDistrictManage = 'ADMIN_DISTRICT_MANAGE';
  static const String adminSystemConfig = 'ADMIN_SYSTEM_CONFIG';

  /// All permission groups structured for UI checkbox rendering
  static const List<PermissionGroup> groups = [
    PermissionGroup(
      title: 'Patient Management',
      icon: '👥',
      description: 'Access patient records, registrations, updates, and removals',
      permissions: [
        PermissionItem(key: patientView, label: 'View Patients List & Profiles', isDefault: true),
        PermissionItem(key: patientCreate, label: 'Register / Create Patients', isDefault: false),
        PermissionItem(key: patientEdit, label: 'Edit Patient Details & Contact', isDefault: false),
        PermissionItem(key: patientDelete, label: 'Delete / Archive Patient Records', isDefault: false),
      ],
    ),
    PermissionGroup(
      title: 'Doctor Management',
      icon: '🩺',
      description: 'Access doctor profiles, credentials, clinics, and verification',
      permissions: [
        PermissionItem(key: dentistView, label: 'View Doctors & Availability', isDefault: false),
        PermissionItem(key: dentistVerify, label: 'Verify Doctor License & Credentials', isDefault: false),
        PermissionItem(key: dentistManage, label: 'Manage Doctor Profiles & Status', isDefault: false),
      ],
    ),
    PermissionGroup(
      title: 'Patient Assignment',
      icon: '🤝',
      description: 'Coordinate patient inquiries with verified local medical specialists',
      permissions: [
        PermissionItem(key: assignmentView, label: 'View Patient Requests & Assigned Doctors', isDefault: false),
        PermissionItem(key: assignmentCreate, label: 'Assign & Reassign Patients to Doctors', isDefault: false),
        PermissionItem(key: assignmentHistoryView, label: 'View Patient Assignment Audit History', isDefault: false),
      ],
    ),
    PermissionGroup(
      title: 'Clinic Management',
      icon: '🏥',
      description: 'Access clinic directories, departments, and partner branches',
      permissions: [
        PermissionItem(key: clinicView, label: 'View Clinics & Facilities', isDefault: false),
        PermissionItem(key: clinicManage, label: 'Manage Clinic Profiles & Branches', isDefault: false),
      ],
    ),
    PermissionGroup(
      title: 'Referral Management',
      icon: '🔗',
      description: 'Monitor doctor-to-doctor and patient clinic referrals',
      permissions: [
        PermissionItem(key: referralView, label: 'View Referral Records & Tracking', isDefault: false),
        PermissionItem(key: referralManage, label: 'Manage & Route Clinical Referrals', isDefault: false),
      ],
    ),
    PermissionGroup(
      title: 'Appointment Management',
      icon: '📅',
      description: 'Oversee, schedule, and reschedule clinic appointments',
      permissions: [
        PermissionItem(key: appointmentView, label: 'View Appointments & Schedules', isDefault: false),
        PermissionItem(key: appointmentManage, label: 'Reschedule, Confirm, or Cancel Appointments', isDefault: false),
      ],
    ),
    PermissionGroup(
      title: 'Problem & Inquiry Pool',
      icon: '💬',
      description: 'Track incoming medical symptoms and triage consultation requests',
      permissions: [
        PermissionItem(key: problemView, label: 'View Patient Problem Requests', isDefault: false),
        PermissionItem(key: problemUpdate, label: 'Update Problem Status & Clinical Notes', isDefault: false),
      ],
    ),
    PermissionGroup(
      title: 'Reports & Analytics',
      icon: '📊',
      description: 'View platform volume, assignment analytics, and district reports',
      permissions: [
        PermissionItem(key: reportView, label: 'View Reports & District Analytics', isDefault: false),
      ],
    ),
  ];

  /// Restricted default permissions for newly created Sub-Admins
  static List<String> get defaultPermissions {
    return [patientView]; // Strictly restricted default per system specification
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
    if (k == 'PATIENT_ADD') return 'Register New Patients';
    if (k == 'DENTIST_CREATE') return 'Register / Add New Doctors';
    if (k == 'DENTIST_EDIT') return 'Edit Doctor Info';
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
