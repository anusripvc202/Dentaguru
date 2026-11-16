import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // GS HEALTH 2-Color Dominant Brand System
  // Color 1: GS Deep Navy Blue (extracted from 'G' and 'HEALTH' in logo)
  static const Color gsNavy = Color(0xFF012A58);
  // Color 2: GS Vibrant Crimson/Coral Red (extracted from 'S' and leaf emblem in logo)
  static const Color gsRed = Color(0xFFFE3434);

  // Brand Colors matching GS HEALTH design system
  static const Color primaryBlue = gsNavy;
  static const Color primaryBlueDark = Color(0xFF001B3B);
  static const Color brandOrange = gsRed;
  static const Color brandOrangeLight = Color(0xFFFF5252);

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
  static const Color statusConfirmedText = primaryBlue;
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
        onSurface: textDark,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 32, color: textDark),
        displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 28, color: textDark),
        displaySmall: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 24, color: textDark),
        headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 22, color: textDark),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 18, color: textDark),
        headlineSmall: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16, color: textDark),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 22, color: textDark),
        titleMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 16, color: textDark),
        titleSmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14, color: textDark),
        bodyLarge: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: textDark),
        bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 13, color: textDark),
        bodySmall: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMedium),
        labelLarge: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: textDark),
        labelMedium: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMedium),
        labelSmall: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: primaryBlue,
        selectionColor: Color(0xFFB3D4FC),
        selectionHandleColor: primaryBlue,
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.04),
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
      tabBarTheme: const TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: textMedium,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: const Color(0xFFF8FAFC),
        filled: true,
        hintStyle: const TextStyle(fontSize: 13, color: textMuted),
        labelStyle: const TextStyle(fontSize: 13, color: textMedium),
        prefixIconColor: primaryBlue,
        suffixIconColor: textMuted,
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
        onSurface: Colors.white,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 32, color: Colors.white),
        displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 28, color: Colors.white),
        displaySmall: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white),
        headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.white),
        headlineSmall: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
        titleMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white),
        titleSmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
        bodyLarge: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
        bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white70),
        bodySmall: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white60),
        labelLarge: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
        labelMedium: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white70),
        labelSmall: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.white60),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: primaryBlue,
        selectionColor: Color(0xFF334155),
        selectionHandleColor: primaryBlue,
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: textMuted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: const Color(0xFF1E293B),
        filled: true,
        hintStyle: const TextStyle(fontSize: 13, color: Colors.white38),
        labelStyle: const TextStyle(fontSize: 13, color: Colors.white70),
        prefixIconColor: primaryBlue,
        suffixIconColor: Colors.white38,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF334155))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF334155))),
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

