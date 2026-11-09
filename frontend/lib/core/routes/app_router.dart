import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/session_service.dart';
import '../widgets/session_gate_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/patient/presentation/screens/patient_dashboard.dart';
import '../../features/patient/presentation/screens/find_doctors_screen.dart';
import '../../features/dentist/presentation/screens/dentist_timeline.dart';
import '../../features/clinic/presentation/screens/clinic_dashboard.dart';
import '../../features/admin/presentation/screens/admin_dashboard.dart';
import '../../features/admin/presentation/screens/sub_admin_dashboard.dart';
import '../../features/auth/presentation/screens/auth_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthScreen();
  }
}

// Router Configurations with Persistent Session Resolution Gate
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    final path = state.uri.path;
    const protectedRoutes = {
      '/patient',
      '/dentist',
      '/clinic',
      '/admin',
      '/sub-admin',
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
        (path == '/clinic' || path == '/dentist' || path == '/patient')) {
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
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
        return AuthScreen(initialRole: role, initialTab: tab);
      },
    ),
    GoRoute(
      path: '/admin-login',
      builder: (context, state) {
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
        return AuthScreen(initialRole: 'admin', initialTab: tab, allowAdminRole: true);
      },
    ),
    GoRoute(
      path: '/admin/auth',
      builder: (context, state) {
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
        return AuthScreen(initialRole: 'admin', initialTab: tab, allowAdminRole: true);
      },
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) {
        final role = state.uri.queryParameters['role'];
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
        return AuthScreen(initialRole: role, initialTab: tab);
      },
    ),
    GoRoute(
      path: '/patient',
      builder: (context, state) => const PatientDashboardScreen(),
    ),
    GoRoute(
      path: '/patient/find-doctors',
      builder: (context, state) => const FindDoctorsScreen(),
    ),
    GoRoute(
      path: '/dentist',
      builder: (context, state) => const DentistTimelineScreen(),
    ),
    GoRoute(
      path: '/clinic',
      builder: (context, state) => const ClinicDashboardScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const AdminDashboardScreen(),
    ),
    GoRoute(
      path: '/sub-admin',
      builder: (context, state) => const SubAdminDashboardScreen(),
    ),
  ],
);
