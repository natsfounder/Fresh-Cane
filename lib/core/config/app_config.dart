/// Application configuration for Fresh Cane POS.
///
/// Contains client-safe public configuration endpoints.
/// Private service-role credentials must NEVER be placed in client code.
class AppConfig {
  const AppConfig._();

  static const String appName = 'Fresh Cane';
  static const String appVersion = '1.0.0';

  /// Remote Supabase Project URL (Sydney ap-southeast-2)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wflhblpdszofrsobjqqq.supabase.co',
  );

  /// Public Client Anon Key
  /// Client operations are constrained by database RLS and transactional RPCs.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndmbGhibHBkc3pvZnJzb2JqcXFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkxNzMwMzcsImV4cCI6MjEwNDc0OTAzN30.DVe5fJgE8TWoR2_M9ZpcOgVGdI1EbhI7TVwOzbYnzkg',
  );
}
