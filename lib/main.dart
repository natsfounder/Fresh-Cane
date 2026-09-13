import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize remote Supabase backend integration
  await SupabaseService.initialize();

  runApp(
    const ProviderScope(
      child: FreshCaneApp(),
    ),
  );
}

/// Root widget for Fresh Cane POS Application.
class FreshCaneApp extends StatelessWidget {
  const FreshCaneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: AppRouter.splash,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
