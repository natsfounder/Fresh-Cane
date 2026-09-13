import 'package:flutter/material.dart';

/// Design system and theme definitions for Fresh Cane POS.
class AppTheme {
  const AppTheme._();

  // Fresh Cane Brand Colors (Sugarcane green / natural palette)
  static const Color primaryGreen = Color(0xFF1B5E20);
  static const Color primaryDark = Color(0xFF0D2B11);
  static const Color accentLime = Color(0xFF43A047);
  static const Color warmCream = Color(0xFFF9FBF7);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1C251D);
  static const Color textSecondary = Color(0xFF5E6D60);
  static const Color errorRed = Color(0xFFC62828);
  static const Color successGreen = Color(0xFF2E7D32);
  static const Color warningOrange = Color(0xFFEF6C00);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        primary: primaryGreen,
        secondary: accentLime,
        surface: warmCream,
        error: errorRed,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: warmCream,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
