import 'package:flutter/material.dart';
import '../presentation/splash_screen.dart';

/// Central route definitions and navigation generator.
class AppRouter {
  const AppRouter._();

  static const String splash = '/';
  static const String login = '/login';
  static const String serverHome = '/server';
  static const String cashierHome = '/cashier';
  static const String adminHome = '/admin';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
      default:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
    }
  }
}
