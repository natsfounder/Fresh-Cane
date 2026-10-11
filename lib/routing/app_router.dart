import 'package:flutter/material.dart';
import '../presentation/admin/admin_home_screen.dart';
import '../presentation/auth/admin_signup_screen.dart';
import '../presentation/auth/login_screen.dart';
import '../presentation/cashier/cashier_home_screen.dart';
import '../presentation/common/software_frozen_screen.dart';
import '../presentation/server/server_home_screen.dart';
import '../presentation/splash_screen.dart';
import '../presentation/super_admin/super_admin_view.dart';

/// Central route definitions and navigation generator.
class AppRouter {
  const AppRouter._();

  static const String splash = '/';
  static const String login = '/login';
  static const String adminSignup = '/admin/signup';
  static const String serverHome = '/server';
  static const String cashierHome = '/cashier';
  static const String adminHome = '/admin';
  static const String superAdminHome = '/super-admin';
  static const String softwareFrozen = '/software-frozen';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
      case login:
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
          settings: settings,
        );
      case adminSignup:
        return MaterialPageRoute(
          builder: (_) => const AdminSignupScreen(),
          settings: settings,
        );
      case serverHome:
        return MaterialPageRoute(
          builder: (_) => const ServerHomeScreen(),
          settings: settings,
        );
      case cashierHome:
        return MaterialPageRoute(
          builder: (_) => const CashierHomeScreen(),
          settings: settings,
        );
      case adminHome:
        return MaterialPageRoute(
          builder: (_) => const AdminHomeScreen(),
          settings: settings,
        );
      case superAdminHome:
        return MaterialPageRoute(
          builder: (_) => const SuperAdminView(),
          settings: settings,
        );
      case softwareFrozen:
        return MaterialPageRoute(
          builder: (_) => const SoftwareFrozenScreen(),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
    }
  }
}
