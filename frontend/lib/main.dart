import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/firebase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await FirebaseService.initialize();
  } catch (e) {
    debugPrint('⚠️ Firebase Service initialization warning: $e');
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
      title: 'Denta Guru',
      debugShowCheckedModeBanner: false,

      // Themes configurations
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,

      // Router configuration
      routerConfig: appRouter,

      // Mobile Device Frame Wrapper for Web / Chrome
      builder: (context, child) {
        final screenWidth = MediaQuery.of(context).size.width;

        // If running on Chrome/Web desktop (>550px), render inside Mobile Phone Bezel Shell
        if (screenWidth > 550) {
          return Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: Center(
              child: Container(
                width: 430,
                height: 880,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(38),
                  border: Border.all(color: const Color(0xFF334155), width: 8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Top Phone Notch Indicator
                    Container(
                      height: 28,
                      color: Colors.white,
                      child: Center(
                        child: Container(
                          width: 130,
                          height: 14,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F172A),
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
                          ),
                        ),
                      ),
                    ),
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
