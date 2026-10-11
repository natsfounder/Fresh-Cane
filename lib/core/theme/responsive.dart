import 'package:flutter/material.dart';

/// Responsive layout utilities for the Fresh Cane POS application.
///
/// Provides breakpoint detection and adaptive values for building
/// layouts that work perfectly across:
/// - Mobile portrait & landscape
/// - Tablet portrait & landscape
///
/// Usage:
/// ```dart
/// final columns = Responsive.gridColumns(context);
/// final padding = Responsive.screenPadding(context);
/// ```
class Responsive {
  const Responsive._();

  // ═══════════════════════════════════════════════════════════════════════════
  // BREAKPOINTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Mobile: width < 600
  static const double mobileBreakpoint = 600;

  /// Tablet: 600 <= width < 1024
  static const double tabletBreakpoint = 1024;

  /// Desktop: width >= 1024
  static const double desktopBreakpoint = 1024;

  // ═══════════════════════════════════════════════════════════════════════════
  // DEVICE TYPE DETECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Whether the current screen width is mobile-sized
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;

  /// Whether the current screen width is tablet-sized
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= mobileBreakpoint && width < tabletBreakpoint;
  }

  /// Whether the current screen width is desktop-sized
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  /// Whether the device is in landscape orientation
  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  /// Whether the device is in portrait orientation
  static bool isPortrait(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.portrait;

  /// Whether the screen is compact (mobile portrait or small window)
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 500;

  // ═══════════════════════════════════════════════════════════════════════════
  // ADAPTIVE VALUES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns a value based on the current breakpoint.
  ///
  /// ```dart
  /// final fontSize = Responsive.value(context, mobile: 14.0, tablet: 16.0);
  /// ```
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYOUT HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Number of grid columns based on screen width.
  /// Accounts for both orientation and device type.
  static int gridColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1200) return 5;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    if (isLandscape(context)) return 3;
    return 2;
  }

  /// Appropriate screen padding based on device type.
  static EdgeInsets screenPadding(BuildContext context) {
    if (isDesktop(context)) return const EdgeInsets.all(24);
    if (isTablet(context)) return const EdgeInsets.all(20);
    return const EdgeInsets.all(16);
  }

  /// Grid item spacing based on device type.
  static double gridSpacing(BuildContext context) {
    if (isDesktop(context)) return 18;
    if (isTablet(context)) return 16;
    return 12;
  }

  /// Card aspect ratio for table grid cards.
  static double tableCardAspectRatio(BuildContext context) {
    if (isDesktop(context)) return 1.4;
    if (isTablet(context)) return 1.3;
    if (isLandscape(context)) return 1.3;
    return 1.2;
  }

  /// Side panel width
  static double sidePanelWidth(BuildContext context) {
    if (isDesktop(context)) return 240;
    if (isTablet(context)) return 220;
    return 260; // overlay panel on mobile — wider for comfortable touch targets
  }

  /// Category panel width
  static double categoryPanelWidth(BuildContext context) {
    if (isCompact(context)) return 95;
    if (isMobile(context)) return 115;
    if (isTablet(context)) return 165;
    return 190;
  }

  /// Navbar height
  static double navbarHeight(BuildContext context) {
    if (isMobile(context)) return 56;
    return 60;
  }

  /// Header height for context view
  static double headerHeight(BuildContext context) {
    if (isMobile(context)) return 48;
    return 56;
  }

  /// Maximum content width for centered layouts (login, splash)
  static double maxContentWidth(BuildContext context) {
    if (isDesktop(context)) return 480;
    if (isTablet(context)) return 440;
    return 400;
  }

  /// Card padding
  static EdgeInsets cardPadding(BuildContext context) {
    if (isDesktop(context)) return const EdgeInsets.all(18);
    if (isTablet(context)) return const EdgeInsets.all(16);
    return const EdgeInsets.all(14);
  }

  /// Font scale factor for tablet/desktop
  static double fontScale(BuildContext context) {
    if (isDesktop(context)) return 1.1;
    if (isTablet(context)) return 1.05;
    return 1.0;
  }
}

/// Convenient BuildContext extensions for responsive queries
extension ResponsiveContext on BuildContext {
  bool get isMobile => Responsive.isMobile(this);
  bool get isTablet => Responsive.isTablet(this);
  bool get isDesktop => Responsive.isDesktop(this);
  bool get isLandscape => Responsive.isLandscape(this);
  bool get isPortrait => Responsive.isPortrait(this);
  bool get isCompact => Responsive.isCompact(this);
}

