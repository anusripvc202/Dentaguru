import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/session_gate_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/patient/presentation/screens/patient_dashboard.dart';
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
      builder: (context, state) => const AdminDashboardScreen(),
    ),
  ],
);
