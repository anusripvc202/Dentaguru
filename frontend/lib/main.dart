import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/firebase_service.dart';
import 'core/services/supabase_service.dart';
import 'core/services/analytics_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await FirebaseService.initialize();
    await SupabaseService.initialize();
    await AnalyticsService.logAppOpen();
  } catch (e) {
    debugPrint('⚠️ Core Services initialization warning: $e');
  }

  runApp(
    const ProviderScope(
      child: DentaGuruApp(),
    ),
  );
}

class DentaGuruApp extends StatelessWidget {
  const DentaGuruApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'DentaGuru Dental Healthcare Platform',
      debugShowCheckedModeBanner: false,

      // Themes configurations
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,

      // Router configuration
      routerConfig: appRouter,

      // Mobile Device Frame Wrapper for Web / Chrome (Neat Mobile App Aesthetics)
      builder: (context, child) {
        final screenWidth = MediaQuery.of(context).size.width;

        // If running on Chrome/Web desktop (>550px), render inside Flagship Mobile Shell
        if (screenWidth > 550) {
          return Scaffold(
            backgroundColor: const Color(0xFF0B132B),
            body: Center(
              child: Container(
                width: 420,
                height: 870,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(44),
                  border: Border.all(color: const Color(0xFF1E293B), width: 10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 40,
                      spreadRadius: 8,
                      offset: const Offset(0, 15),
                    ),
                    BoxShadow(
                      color: const Color(0xFF0052CC).withValues(alpha: 0.25),
                      blurRadius: 60,
                      spreadRadius: -10,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Flagship Phone Dynamic Island / Notch Bar
                    Container(
                      height: 32,
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '9:41',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          Container(
                            width: 110,
                            height: 18,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          const Row(
                            children: [
                              Icon(Icons.wifi_rounded, size: 13, color: Color(0xFF0F172A)),
                              SizedBox(width: 4),
                              Icon(Icons.battery_5_bar_rounded, size: 14, color: Color(0xFF0F172A)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Main App Content Window
                    Expanded(child: child ?? const SizedBox()),
                  ],
                ),
              ),
            ),
          );
        }
        return child ?? const SizedBox();
      },
    );
  }
}
