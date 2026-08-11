import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // Brand Colors matching DentaGuru design mockup & logo
  static const Color primaryBlue = Color(0xFF0052CC);
  static const Color primaryBlueDark = Color(0xFF0B46A4);
  static const Color brandOrange = Color(0xFFFF7A00);
  static const Color brandOrangeLight = Color(0xFFFF9500);

  // Soft Tint & Background Colors
  static const Color softBlueBg = Color(0xFFF4F7FC);
  static const Color cardBg = Colors.white;
  static const Color softBlueCard = Color(0xFFEBF2FE);
  static const Color softBlueBorder = Color(0xFFD4E3FC);

  // Text Colors
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMedium = Color(0xFF475569);
  static const Color textMuted = Color(0xFF8C9BAB);

  // Status Colors
  static const Color statusConfirmedBg = Color(0xFFEBF2FE);
  static const Color statusConfirmedText = Color(0xFF0052CC);
  static const Color statusCancelBg = Color(0xFFFEE2E2);
  static const Color statusCancelText = Color(0xFFEF4444);

  // 1. LIGHT MODE THEME
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: softBlueBg,
      colorScheme: const ColorScheme.light(
        primary: primaryBlue,
        secondary: brandOrange,
        tertiary: primaryBlueDark,
        surface: cardBg,
        onPrimary: Colors.white,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme).copyWith(
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 22, color: textDark),
        titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16, color: textDark),
        bodyLarge: GoogleFonts.plusJakartaSans(fontSize: 14, color: textDark),
        bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMedium),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0.5,
        shadowColor: Colors.black.withOpacity(0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFEEF2F6), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: softBlueBg,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: primaryBlue),
        titleTextStyle: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 20),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: const Color(0xFFF8FAFC),
        filled: true,
        hintStyle: const TextStyle(fontSize: 12, color: textMuted),
        labelStyle: const TextStyle(fontSize: 13, color: textMedium),
        prefixIconColor: primaryBlue,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: primaryBlue, width: 2)),
      ),
    );
  }

  // 2. DARK MODE THEME
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      colorScheme: const ColorScheme.dark(
        primary: primaryBlue,
        secondary: brandOrange,
        surface: Color(0xFF1E293B),
        onPrimary: Colors.white,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme).copyWith(
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
        titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white),
        bodyLarge: GoogleFonts.plusJakartaSans(fontSize: 14, color: textDark),
        bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 13, color: textDark),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: const Color(0xFFF8FAFC),
        filled: true,
        hintStyle: const TextStyle(fontSize: 12, color: textMuted),
        labelStyle: const TextStyle(fontSize: 13, color: textMedium),
        prefixIconColor: primaryBlue,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: primaryBlue, width: 2)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E293B),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
      ),
    );
  }
}

