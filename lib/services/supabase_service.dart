import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/app_config.dart';

/// Central service for Supabase initialization and client access.
class SupabaseService {
  const SupabaseService._();

  /// Initialize Supabase Flutter SDK with client-safe configuration.
  static Future<void> initialize() async {
    try {
      // ignore: deprecated_member_use
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        // ignore: deprecated_member_use
        anonKey: AppConfig.supabaseAnonKey,
        debug: kDebugMode,
      );
    } catch (e) {
      debugPrint('Supabase initialization failed: $e');
      rethrow;
    }
  }

  /// Get the active Supabase client instance.
  static SupabaseClient get client => Supabase.instance.client;

  /// Current authenticated user session if present.
  static Session? get currentSession => client.auth.currentSession;

  /// Current authenticated user if present.
  static User? get currentUser => client.auth.currentUser;

  /// Check whether an authenticated session exists.
  static bool get isAuthenticated => currentSession != null;
}
