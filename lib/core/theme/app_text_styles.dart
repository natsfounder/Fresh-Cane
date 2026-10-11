import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Centralized typography system for the Fresh Cane POS application.
///
/// Uses Google Fonts **Outfit** — a clean, geometric sans-serif that feels
/// modern and premium. All text styles reference [AppColors] for consistency.
class AppTextStyles {
  const AppTextStyles._();

  // ═══════════════════════════════════════════════════════════════════════════
  // BASE FONT FAMILY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Base text style with Outfit font applied
  static TextStyle get _base => GoogleFonts.outfit();

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPLAY / HERO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Display Large — Splash screen brand name
  static TextStyle get displayLarge => _base.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.textOnPrimary,
        letterSpacing: 0.5,
      );

  /// Display Medium — Section hero titles
  static TextStyle get displayMedium => _base.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: 0.2,
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADINGS
  // ═══════════════════════════════════════════════════════════════════════════

  /// H1 — Screen titles
  static TextStyle get h1 => _base.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: -0.2,
      );

  /// H2 — Section titles
  static TextStyle get h2 => _base.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: 0.1,
      );

  /// H3 — Card titles, dialog titles
  static TextStyle get h3 => _base.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  /// H4 — Sub-section titles
  static TextStyle get h4 => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // BODY TEXT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Body Large — Primary content text
  static TextStyle get bodyLarge => _base.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      );

  /// Body Medium — Standard content
  static TextStyle get bodyMedium => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      );

  /// Body Small — Secondary content
  static TextStyle get bodySmall => _base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // LABELS & BUTTONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Label Large — Button text, prominent labels
  static TextStyle get labelLarge => _base.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      );

  /// Button text alias
  static TextStyle get buttonText => labelLarge;

  /// Label Medium — Secondary button text
  static TextStyle get labelMedium => _base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      );

  /// Label Small — Chips, pills, tiny labels
  static TextStyle get labelSmall => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // CAPTIONS & OVERLINES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Caption — Small descriptive text
  static TextStyle get caption => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  /// Overline — Category headers, uppercase labels
  static TextStyle get overline => _base.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: AppColors.textSecondary,
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // NUMERIC / FINANCIAL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Money Large — Grand totals, hero amounts
  static TextStyle get moneyLarge => _base.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: AppColors.primaryGreen,
        letterSpacing: -0.5,
      );

  /// Money Medium — Order totals
  static TextStyle get moneyMedium => _base.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppColors.primaryGreen,
      );

  /// Money Small — Line item prices
  static TextStyle get moneySmall => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // SPECIAL PURPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Navbar brand name
  static TextStyle get navbarBrand => _base.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.primaryGreen,
        letterSpacing: 0.3,
      );

  /// Table number (large, bold)
  static TextStyle get tableNumber => _base.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
        letterSpacing: -0.3,
      );

  /// Status badge text
  static TextStyle get statusBadge => _base.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      );

  /// AppBar title
  static TextStyle get appBarTitle => _base.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textOnPrimary,
        letterSpacing: 0.2,
      );

  /// AppBar subtitle
  static TextStyle get appBarSubtitle => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: Colors.white70,
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER — Generate full TextTheme for ThemeData
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generates a complete Material [TextTheme] using Outfit
  static TextTheme get textTheme => GoogleFonts.outfitTextTheme();
}
