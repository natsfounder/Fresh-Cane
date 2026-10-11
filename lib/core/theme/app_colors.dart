import 'package:flutter/material.dart';

/// Centralized color palette for the Fresh Cane POS application.
///
/// Every color used in the application MUST be referenced from this file.
/// This is the single source of truth for the entire design system.
///
/// Color groups:
/// - **Brand** — Extracted from the official Fresh Cane logo
/// - **Semantic** — Mapped brand colors to UI roles
/// - **Status** — Table/order/customer lifecycle states
/// - **Surface** — Backgrounds, cards, panels
/// - **Text** — Typography colors
/// - **Border** — Dividers, outlines, separators
/// - **Glass** — Liquid glass effect constants
class AppColors {
  const AppColors._();

  // ═══════════════════════════════════════════════════════════════════════════
  // BRAND PALETTE — Extracted from Fresh Cane Logo
  // ═══════════════════════════════════════════════════════════════════════════

  /// Deep Forest Green — Mockup brand primary (Sidebars, Login card, rails)
  static const Color darkForest = Color(0xFF0F2E1E);

  /// Darkest forest green for deep contrast
  static const Color darkForestDarker = Color(0xFF0A2215);

  /// Dark forest surface for cards and elevated panels on dark bg
  static const Color darkForestSurface = Color(0xFF133824);

  /// Dark forest container / card bg
  static const Color darkForestCard = Color(0xFF163E28);

  /// Dark forest subtle border
  static const Color darkForestBorder = Color(0xFF265036);

  /// Active pill selection green (Mockup rounded pills)
  static const Color activeGreenPill = Color(0xFF266540);

  /// Brand Emerald Green — Primary CTA buttons, action highlights
  static const Color brandEmerald = Color(0xFF2D6A4F);

  /// Deep Forest Green — Logo text and outer ring
  /// Primary brand color for headers, buttons, hero elements
  static const Color primaryGreen = Color(0xFF2D6A4F);

  /// Fresh Cane Green — Sugarcane body / leaves
  /// Secondary accent for highlights, active states, badges
  static const Color secondaryGreen = Color(0xFF7CB342);

  /// Sugarcane Wood Brown — Warm earthy accent
  /// Used for warm surfaces, earthy borders, organic accents
  static const Color woodBrown = Color(0xFF8D6E4C);

  // ─── Brand Variants ────────────────────────────────────────────────────────

  /// Darkest green for deep contrast (AppBar, dark headers)
  static const Color primaryDark = Color(0xFF0F2E1E);

  /// Medium primary for secondary emphasis
  static const Color primaryMedium = Color(0xFF266540);

  /// Very light primary tint for backgrounds
  static const Color primaryLight = Color(0xFFE8F5E9);

  /// Bright secondary for strong accents
  static const Color secondaryBright = Color(0xFF8BC34A);

  /// Soft secondary for fills/backgrounds
  static const Color secondaryLight = Color(0xFFF1F8E9);

  /// Dark brown for text on wood surfaces
  static const Color woodDark = Color(0xFF6D5339);

  /// Light warm tone for backgrounds
  static const Color woodLight = Color(0xFFEFEBE9);

  /// Very subtle wood wash
  static const Color woodMist = Color(0xFFF5F0EB);

  /// Rich warm wood for prominent wooden accents
  static const Color woodWarm = Color(0xFF7A5C3D);

  /// Warm café gold accent
  static const Color accentGold = Color(0xFFC89B3C);

  /// Soft tint for gold badges and highlights
  static const Color accentGoldLight = Color(0xFFFFF9E8);

  /// Subtle gold border
  static const Color accentGoldBorder = Color(0xFFF3E5AB);

  /// Soft cream tone for elevated café cards
  static const Color creamSoft = Color(0xFFFFFDF9);

  // ═══════════════════════════════════════════════════════════════════════════
  // SEMANTIC COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary action color (buttons, links, active states)
  static const Color primary = primaryGreen;

  /// Secondary action color (accents, highlights)
  static const Color secondary = secondaryGreen;

  /// Accent warm color (earthy elements)
  static const Color accent = woodBrown;

  /// Error / danger / destructive
  static const Color error = Color(0xFFE53935);

  /// Error light background
  static const Color errorLight = Color(0xFFFCEBEB);

  /// Warning / caution
  static const Color warning = Color(0xFFEF6C00);

  /// Warning light background
  static const Color warningLight = Color(0xFFFFF3E0);

  /// Success
  static const Color success = secondaryGreen;

  /// Success light background
  static const Color successLight = secondaryLight;

  /// Info / neutral action
  static const Color info = Color(0xFF1976D2);

  /// Info light background
  static const Color infoLight = Color(0xFFE3F2FD);

  // ═══════════════════════════════════════════════════════════════════════════
  // STATUS COLORS — Table / Order / Customer Lifecycle
  // ═══════════════════════════════════════════════════════════════════════════

  /// Available table status - Crisp Emerald Green
  static const Color statusAvailable = Color(0xFF059669);
  static const Color statusAvailableBg = Color(0xFFECFDF5);
  static const Color statusAvailableBorder = Color(0xFFA7F3D0);

  /// Occupied table status - Warm Amber / Coral
  static const Color statusOccupied = Color(0xFFEA580C);
  static const Color statusOccupiedBg = Color(0xFFFFF7ED);
  static const Color statusOccupiedBorder = Color(0xFFFED7AA);

  /// Active customer / order
  static const Color statusActive = secondaryGreen;
  static const Color statusActiveBg = secondaryLight;

  /// Finished customer
  static const Color statusFinished = primaryGreen;
  static const Color statusFinishedBg = primaryLight;

  /// Billed
  static const Color statusBilled = Color(0xFF1976D2);
  static const Color statusBilledBg = Color(0xFFE3F2FD);

  /// Closed
  static const Color statusClosed = Color(0xFF757575);
  static const Color statusClosedBg = Color(0xFFF5F5F5);

  /// Cancelled order
  static const Color statusCancelled = Color(0xFF9E9E9E);
  static const Color statusCancelledBg = Color(0xFFFAFAFA);

  /// Billing ready (amber)
  static const Color statusBillingReady = Color(0xFFB45309);
  static const Color statusBillingReadyBg = Color(0xFFFEF3C7);
  static const Color statusBillingReadyBorder = Color(0xFFFDE68A);

  // ═══════════════════════════════════════════════════════════════════════════
  // SURFACE COLORS — Backgrounds, Cards, Panels
  // ═══════════════════════════════════════════════════════════════════════════

  /// Main scaffold background — warm off-white
  static const Color surface = Color(0xFFFAF9F6);

  /// Card / elevated surface
  static const Color cardSurface = Color(0xFFFFFFFF);

  /// Aliases for background and card surfaces
  static const Color backgroundLight = surface;
  static const Color surfaceLight = cardSurface;

  /// Warm neutral surface (side panel, secondary areas)
  static const Color warmSurface = Color(0xFFF5F3EE);

  /// Slightly tinted surface for contrast
  static const Color tintedSurface = Color(0xFFF0EDE6);

  /// Category panel background — Dark Forest Green (Mockup standard)
  static const Color categoryPanelBg = darkForest;

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary text — near black
  static const Color textPrimary = Color(0xFF1A1A1A);

  /// Secondary text — muted
  static const Color textSecondary = Color(0xFF6B6B6B);

  /// Tertiary text — hint / placeholder
  static const Color textTertiary = Color(0xFF9E9E9E);

  /// Hint text color
  static const Color textHint = textTertiary;

  /// Text on primary color (white)
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  /// Text on secondary surfaces
  static const Color textOnSecondary = Color(0xFF33691E);

  /// Text on wood-colored surfaces
  static const Color textOnWood = Color(0xFF4E342E);

  // ═══════════════════════════════════════════════════════════════════════════
  // BORDER COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Light border — cards, inputs
  static const Color borderLight = Color(0xFFE8E5DE);

  /// Medium border — dividers, separators
  static const Color borderMedium = Color(0xFFD5D1C8);

  /// Strong border — active / focused
  static const Color borderStrong = Color(0xFF9E9A91);

  /// Primary border — focused inputs, active cards
  static const Color borderPrimary = primaryGreen;

  /// Brown border — organic elements
  static const Color borderWood = Color(0xFFD7CCC8);

  // ═══════════════════════════════════════════════════════════════════════════
  // LIQUID GLASS EFFECT CONSTANTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Glass surface overlay (semi-transparent white)
  static const Color glassSurface = Color(0x33FFFFFF);

  /// Glass surface — stronger opacity
  static const Color glassSurfaceStrong = Color(0x66FFFFFF);

  /// Glass border highlight (top-left light source)
  static const Color glassBorderHighlight = Color(0x40FFFFFF);

  /// Glass border shadow (bottom-right)
  static const Color glassBorderShadow = Color(0x15000000);

  /// Glass shadow color
  static const Color glassShadow = Color(0x18000000);

  /// Glass green tint (for primary-themed glass)
  static const Color glassGreenTint = Color(0x152D5A27);

  /// Glass brown tint (for warm-themed glass)
  static const Color glassBrownTint = Color(0x128D6E4C);

  // ═══════════════════════════════════════════════════════════════════════════
  // GRADIENT PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary hero gradient (splash, headers)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primaryGreen, primaryMedium],
  );

  /// Subtle surface gradient for backgrounds
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [surface, warmSurface],
  );

  /// Category panel / rail gradient (Dark Forest mockup)
  static const LinearGradient woodGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [darkForest, darkForestDarker],
  );

  /// Glass overlay gradient (light source effect)
  static const LinearGradient glassOverlay = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x20FFFFFF),
      Color(0x08FFFFFF),
      Color(0x05FFFFFF),
    ],
  );

  /// Button gradient
  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryMedium, primaryGreen],
  );

  /// Deep forest header gradient
  static const LinearGradient forestHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [darkForestDarker, darkForest, darkForestSurface],
  );

  /// Warm cream card gradient
  static const LinearGradient creamCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [creamSoft, surface],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // SHADOW PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Subtle card shadow
  static List<BoxShadow> get shadowSmall => const [
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ];

  /// Medium elevation shadow
  static List<BoxShadow> get shadowMedium => const [
        BoxShadow(
          color: Color(0x12000000),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ];

  /// High elevation shadow
  static List<BoxShadow> get shadowLarge => const [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 20,
          offset: Offset(0, 6),
        ),
      ];

  /// Glass-specific shadow with green tint
  static List<BoxShadow> get shadowGlass => const [
        BoxShadow(
          color: Color(0x10000000),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
        BoxShadow(
          color: Color(0x082D5A27),
          blurRadius: 30,
          offset: Offset(0, 2),
          spreadRadius: -4,
        ),
      ];

  /// Green glow shadow for active/available states
  static List<BoxShadow> get glowGreen => const [
        BoxShadow(
          color: Color(0x20059669),
          blurRadius: 12,
          spreadRadius: -2,
        ),
      ];

  /// Amber glow shadow for occupied states
  static List<BoxShadow> get glowRed => const [
        BoxShadow(
          color: Color(0x20EA580C),
          blurRadius: 12,
          spreadRadius: -2,
        ),
      ];

  // ═══════════════════════════════════════════════════════════════════════════
  // DIMENSIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Card border radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXL = 20.0;
  static const double radiusExtraLarge = 20.0;
  static const double radiusRound = 100.0;

  /// Glass blur sigma
  static const double glassBlurLight = 8.0;
  static const double glassBlurMedium = 15.0;
  static const double glassBlurHeavy = 25.0;

  /// Minimum touch target
  static const double minTouchTarget = 44.0;
}
