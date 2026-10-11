import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

/// Design system and theme definitions for Fresh Cane POS.
///
/// This file integrates [AppColors] and [AppTextStyles] into the Material
/// [ThemeData] used by the application. All color references point to
/// the centralized [AppColors] palette.
class AppTheme {
  const AppTheme._();

  // ─── Backwards Compatibility Aliases ───────────────────────────────────────
  // These map old names → new AppColors values so existing code compiles
  // without modification. Gradually migrate to AppColors references directly.

  static const Color teal600 = AppColors.primaryGreen;
  static const Color teal50 = AppColors.primaryLight;
  static const Color teal800 = AppColors.primaryDark;
  static const Color green400 = AppColors.secondaryGreen;
  static const Color green50 = AppColors.secondaryLight;
  static const Color red400 = AppColors.error;
  static const Color red50 = AppColors.errorLight;
  static const Color gray400 = AppColors.borderStrong;
  static const Color gray50 = AppColors.surface;
  static const Color nearBlack = AppColors.textPrimary;
  static const Color gray600 = AppColors.textSecondary;

  // ─── POS Structural Dimensions ─────────────────────────────────────────────
  static const double cardRadius = AppColors.radiusMedium;
  static const double buttonRadius = AppColors.radiusSmall;
  static const double minTouchTarget = AppColors.minTouchTarget;

  // ─── Semantic Mappings ─────────────────────────────────────────────────────
  static const Color primaryTeal = AppColors.primaryGreen;
  static const Color primaryTealLight = AppColors.primaryLight;
  static const Color primaryTealDark = AppColors.primaryDark;
  static const Color statusAvailable = AppColors.statusAvailable;
  static const Color statusAvailableBg = AppColors.statusAvailableBg;
  static const Color statusOccupied = AppColors.statusOccupied;
  static const Color statusOccupiedBg = AppColors.statusOccupiedBg;
  static const Color neutralBorder = AppColors.borderStrong;
  static const Color neutralSurface = AppColors.surface;

  // ─── Legacy Brand Colors ───────────────────────────────────────────────────
  static const Color primaryGreen = AppColors.primaryGreen;
  static const Color primaryDark = AppColors.primaryDark;
  static const Color accentLime = AppColors.secondaryGreen;
  static const Color warmCream = AppColors.surface;
  static const Color surfaceCard = AppColors.cardSurface;
  static const Color textPrimary = AppColors.textPrimary;
  static const Color textSecondary = AppColors.textSecondary;
  static const Color errorRed = AppColors.error;
  static const Color successGreen = AppColors.secondaryGreen;
  static const Color warningOrange = AppColors.warning;
  static const Color accentAmber = AppColors.warning;

  // ─── Extended Palette ──────────────────────────────────────────────────────
  static const Color surfaceLight = AppColors.surface;
  static const Color borderLight = AppColors.borderLight;
  static const Color borderMedium = AppColors.borderMedium;
  static const Color cardShadow = Color(0x0F000000);
  static const Color juiceOrange = Color(0xFFFF8F00);
  static const Color milkshakePurple = Color(0xFF7B1FA2);
  static const Color snackAmber = Color(0xFFE65100);

  // ─── Elevation Tokens ──────────────────────────────────────────────────────
  static List<BoxShadow> get elevationLow => AppColors.shadowSmall;
  static List<BoxShadow> get elevationMedium => AppColors.shadowMedium;
  static List<BoxShadow> get elevationHigh => AppColors.shadowLarge;

  // ─── Theme Data ────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      textTheme: AppTextStyles.textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryGreen,
        primary: AppColors.primaryGreen,
        secondary: AppColors.secondaryGreen,
        surface: AppColors.surface,
        error: AppColors.error,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
          side: const BorderSide(color: AppColors.borderLight),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderMedium),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderMedium),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.primaryGreen, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        labelStyle: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        hintStyle: GoogleFonts.outfit(
          fontSize: 13,
          color: AppColors.textTertiary,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusXL),
        ),
        elevation: 8,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
          textStyle: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: const BorderSide(color: AppColors.borderMedium),
          textStyle: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryGreen,
          textStyle: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderLight,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 4,
      ),
    );
  }
}
