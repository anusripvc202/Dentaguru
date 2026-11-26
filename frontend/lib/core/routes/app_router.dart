import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/session_service.dart';
import '../services/patient_problem_service.dart';
import '../widgets/session_gate_screen.dart';
import '../../features/patient/presentation/screens/patient_dashboard.dart';
import '../../features/patient/presentation/screens/patient_profile_completion_screen.dart';
import '../../features/patient/presentation/screens/find_doctors_screen.dart';
import '../../features/patient/presentation/screens/talk_to_dentist_now_screen.dart';
import '../../features/patient/presentation/screens/ai_triage_screen.dart';
import '../../features/dentist/presentation/screens/dentist_timeline.dart';
import '../../features/dentist/presentation/screens/doctor_patient_record_screen.dart';
import '../../features/dentist/presentation/screens/doctor_profile_screen.dart';
import '../../features/clinic/presentation/screens/clinic_dashboard.dart';
import '../../features/clinic/presentation/screens/clinic_profile_screen.dart';
import '../../features/admin/presentation/screens/admin_dashboard.dart';
import '../../features/admin/presentation/screens/admin_profile_screen.dart';
import '../../features/admin/presentation/screens/admin_referrals_screen.dart';
import '../../features/admin/presentation/screens/sub_admin_dashboard.dart';
import '../../features/auth/presentation/screens/auth_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthScreen(initialTab: 1);
  }
}

// Router Configurations with Persistent Session Resolution Gate
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    final path = state.uri.path;
    const protectedRoutes = {
      '/patient',
      '/patient/find-doctors',
      '/patient/talk-to-dentist',
      '/patient/ai-triage',
      '/patient/complete-profile',
      '/dentist',
      '/clinic',
      '/admin',
      '/sub-admin',
    };
    const patientServiceRoutes = {
      '/patient/find-doctors',
      '/patient/talk-to-dentist',
      '/patient/ai-triage',
    };

    if (!protectedRoutes.contains(path)) {
      return null;
    }

    var session = SessionService().currentSession;
    session ??= await SessionService().restoreAppSession();

    if (session == null || session.isExpired || session.token.trim().isEmpty) {
      return '/login';
    }

    final expectedRoute = session.targetRoute;
    final userRole = session.role.trim().toLowerCase();
    // Allow Admins & Sub-Admins to navigate and inspect Clinic, Doctor, and Patient dashboards
    if (userRole.contains('admin') &&
        (path == '/clinic' || path == '/dentist' || path == '/patient' || patientServiceRoutes.contains(path))) {
      return null;
    }
    if (userRole == 'patient' && (patientServiceRoutes.contains(path) || path == '/patient/complete-profile')) {
      if (patientServiceRoutes.contains(path) &&
          !PatientProblemService().currentPatient.isProfileComplete) {
        final nextUri = Uri.encodeComponent(state.uri.toString());
        final title = path == '/patient/find-doctors'
            ? 'Find Doctors'
            : (path == '/patient/talk-to-dentist' ? 'Talk to a Doctor' : 'AI Health Triage');
        return '/patient/complete-profile?next=$nextUri&service=${Uri.encodeComponent(title)}';
      }
      return null;
    }
    if (path != expectedRoute) {
      return expectedRoute;
    }

    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SessionGateScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) {
        final role = state.uri.queryParameters['role'];
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '1') ?? 1;
        return AuthScreen(initialRole: role, initialTab: tab);
      },
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) {
        final role = state.uri.queryParameters['role'];
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
        return AuthScreen(initialRole: role, initialTab: tab);
      },
    ),
    GoRoute(
      path: '/admin-login',
      builder: (context, state) => const AuthScreen(initialTab: 1),
    ),
    GoRoute(
      path: '/admin/auth',
      builder: (context, state) => const AuthScreen(initialTab: 1),
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) {
        final role = state.uri.queryParameters['role'];
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '1') ?? 1;
        return AuthScreen(initialRole: role, initialTab: tab);
      },
    ),
    GoRoute(
      path: '/patient',
      builder: (context, state) {
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
        final openBookingDoctorId = state.uri.queryParameters['openBookingDoctorId'];
        final bookingDate = state.uri.queryParameters['bookingDate'];
        final bookingSlot = state.uri.queryParameters['bookingSlot'];
        final bookingMode = state.uri.queryParameters['bookingMode'];
        return PatientDashboardScreen(
          initialTabIndex: tab,
          openBookingDoctorId: openBookingDoctorId,
          initialBookingDate: bookingDate,
          initialBookingSlot: bookingSlot,
          initialBookingMode: bookingMode,
        );
      },
    ),
    GoRoute(
      path: '/patient/complete-profile',
      builder: (context, state) {
        final nextRaw = state.uri.queryParameters['next'];
        final serviceTitle = state.uri.queryParameters['service'];
        return PatientProfileCompletionScreen(
          serviceTitle: serviceTitle,
          onCompleted: () {
            if (nextRaw != null && nextRaw.isNotEmpty) {
              context.go(Uri.decodeComponent(nextRaw));
            } else {
              context.go('/patient');
            }
          },
        );
      },
    ),
    GoRoute(
      path: '/patient/find-doctors',
      builder: (context, state) => const FindDoctorsScreen(),
    ),
    GoRoute(
      path: '/patient/talk-to-dentist',
      builder: (context, state) => const TalkToDentistNowScreen(),
    ),
    GoRoute(
      path: '/patient/ai-triage',
      builder: (context, state) {
        final initialSymptom = state.uri.queryParameters['symptom'];
        return AiTriageScreen(initialSymptom: initialSymptom);
      },
    ),
    GoRoute(
      path: '/dentist',
      builder: (context, state) {
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
        return DentistTimelineScreen(initialTabIndex: tab);
      },
    ),
    GoRoute(
      path: '/dentist/patient-record',
      builder: (context, state) {
        final patient = state.extra is PatientProfile
            ? state.extra as PatientProfile
            : PatientProblemService().currentPatient;
        return DoctorPatientRecordScreen(patient: patient);
      },
    ),
    GoRoute(
      path: '/dentist/profile',
      builder: (context, state) => const DoctorProfileScreen(),
    ),
    GoRoute(
      path: '/clinic',
      builder: (context, state) => const ClinicDashboardScreen(),
    ),
    GoRoute(
      path: '/clinic/profile',
      builder: (context, state) => const ClinicProfileScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const AdminDashboardScreen(),
    ),
    GoRoute(
      path: '/admin/profile',
      builder: (context, state) => const AdminProfileScreen(),
    ),
    GoRoute(
      path: '/admin/referrals',
      builder: (context, state) => const AdminReferralsScreen(),
    ),
    GoRoute(
      path: '/sub-admin',
      builder: (context, state) => const SubAdminDashboardScreen(),
    ),
  ],
);
