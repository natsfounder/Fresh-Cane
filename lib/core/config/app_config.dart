import 'package:flutter/foundation.dart';

/// Application configuration for Fresh Cane POS.
///
/// Contains client-safe public configuration endpoints.
/// Private service-role credentials must NEVER be placed in client code.
class AppConfig {
  const AppConfig._();

  static const String appName = 'Fresh Cane';
  static const String appVersion = '1.0.0';

  /// Staging project reference constant for explicit development workflows.
  static const String _stagingSupabaseUrl =
      'https://wflhblpdszofrsobjqqq.supabase.co';
  static const String _stagingSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndmbGhibHBkc3pvZnJzb2JqcXFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkxNzMwMzcsImV4cCI6MjEwNDc0OTAzN30.DVe5fJgE8TWoR2_M9ZpcOgVGdI1EbhI7TVwOzbYnzkg';

  /// Production project reference constant (nnakfnqgdhiblcolbphr).
  static const String _productionSupabaseUrl =
      'https://nnakfnqgdhiblcolbphr.supabase.co';
  static const String _productionSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5uYWtmbnFnZGhpYmxjb2xicGhyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE2MzgxMjUsImV4cCI6MjEwNzIxNDEyNX0.Swak3hI6U9thrJdLreg-33BBFEKPz3HHsBfMdxNqyXo';

  /// Raw ENVIRONMENT passed via compile-time definition.
  static const String _rawEnvironment = String.fromEnvironment('ENVIRONMENT');

  /// Active Environment: 'staging' or 'production'.
  /// Defaults to 'staging' on the Staging branch.
  static String get environment {
    if (_rawEnvironment.isNotEmpty) {
      return _rawEnvironment.toLowerCase().trim();
    }
    return 'staging';
  }

  /// Whether the current build is targeting production.
  static bool get isProduction => environment == 'production';

  /// Whether the current build is targeting staging.
  static bool get isStaging => environment == 'staging';

  /// Raw Supabase Project URL passed via compile-time definition.
  static const String _rawSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Raw Public Client Anon Key passed via compile-time definition.
  static const String _rawSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Resolved Supabase URL.
  static String get supabaseUrl {
    if (isProduction) {
      return _rawSupabaseUrl.isNotEmpty ? _rawSupabaseUrl : _productionSupabaseUrl;
    }
    return _rawSupabaseUrl.isNotEmpty ? _rawSupabaseUrl : _stagingSupabaseUrl;
  }

  /// Resolved Supabase Anon Key.
  static String get supabaseAnonKey {
    if (isProduction) {
      return _rawSupabaseAnonKey.isNotEmpty
          ? _rawSupabaseAnonKey
          : _productionSupabaseAnonKey;
    }
    return _rawSupabaseAnonKey.isNotEmpty
        ? _rawSupabaseAnonKey
        : _stagingSupabaseAnonKey;
  }

  /// Validates environment configuration before SDK initialization.
  static void validate() {
    validateConfig(
      env: environment,
      rawEnvProvided: _rawEnvironment.isNotEmpty,
      rawUrl: _rawSupabaseUrl,
      rawKey: _rawSupabaseAnonKey,
      isRelease: kReleaseMode,
    );
  }

  /// Pure validation logic testable in automated tests and runtime.
  static void validateConfig({
    required String env,
    required bool rawEnvProvided,
    required String rawUrl,
    required String rawKey,
    required bool isRelease,
  }) {
    // 1. Release builds MUST explicitly specify ENVIRONMENT
    if (isRelease && !rawEnvProvided) {
      throw StateError(
        'RELEASE CONFIGURATION ERROR: Explicit ENVIRONMENT definition is required for release builds.\n'
        'Specify either:\n'
        '  --dart-define=ENVIRONMENT=staging\n'
        'or:\n'
        '  --dart-define=ENVIRONMENT=production --dart-define=SUPABASE_URL=https://<prod-ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<prod-anon-key>',
      );
    }

    // 2. Validate environment value
    if (env != 'staging' && env != 'production') {
      throw StateError(
        'UNSUPPORTED ENVIRONMENT: "$env". Valid environments are strictly "staging" or "production".',
      );
    }

    // 3. Production validation
    if (env == 'production') {
      final resolvedUrl = rawUrl.isNotEmpty ? rawUrl : _productionSupabaseUrl;
      final resolvedKey = rawKey.isNotEmpty ? rawKey : _productionSupabaseAnonKey;

      if (resolvedUrl.isEmpty) {
        throw StateError(
          'PRODUCTION CONFIGURATION ERROR: SUPABASE_URL was not supplied.\n'
          'Production builds require explicit compile-time flags:\n'
          '  --dart-define=SUPABASE_URL=https://<prod-ref>.supabase.co\n'
          '  --dart-define=SUPABASE_ANON_KEY=<prod-anon-key>',
        );
      }
      final uri = Uri.tryParse(resolvedUrl);
      if (uri == null || uri.scheme != 'https' || !uri.hasAuthority || uri.host.isEmpty) {
        throw StateError(
          'PRODUCTION CONFIGURATION ERROR: SUPABASE_URL must be a valid HTTPS URL (got: "$resolvedUrl").',
        );
      }
      if (resolvedUrl.contains('wflhblpdszofrsobjqqq')) {
        throw StateError(
          'PRODUCTION ISOLATION ERROR: Production build cannot point to the Staging Supabase project URL.',
        );
      }
      if (resolvedKey.isEmpty || resolvedKey.length < 30) {
        throw StateError(
          'PRODUCTION CONFIGURATION ERROR: SUPABASE_ANON_KEY was missing or malformed.',
        );
      }
    } else {
      // 4. Staging validation
      final resolvedUrl = rawUrl.isNotEmpty ? rawUrl : _stagingSupabaseUrl;
      final resolvedKey = rawKey.isNotEmpty ? rawKey : _stagingSupabaseAnonKey;

      if (resolvedUrl.isEmpty || !resolvedUrl.startsWith('https://')) {
        throw StateError(
          'STAGING CONFIGURATION ERROR: Invalid Supabase URL: $resolvedUrl',
        );
      }
      if (resolvedKey.isEmpty || resolvedKey.length < 30) {
        throw StateError(
          'STAGING CONFIGURATION ERROR: Missing or invalid Supabase Anon Key.',
        );
      }
    }
  }
}
