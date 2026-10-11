import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_cane/core/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('1. Environment Isolation Verification (All 8 Scenarios)', () {
    test('Scenario 1: Debug build with default development configuration', () {
      expect(
        () => AppConfig.validateConfig(
          env: 'staging',
          rawEnvProvided: false,
          rawUrl: '',
          rawKey: '',
          isRelease: false,
        ),
        returnsNormally,
      );
    });

    test('Scenario 2: Release build explicitly configured for Staging', () {
      expect(
        () => AppConfig.validateConfig(
          env: 'staging',
          rawEnvProvided: true,
          rawUrl: '',
          rawKey: '',
          isRelease: true,
        ),
        returnsNormally,
      );
    });

    test('Scenario 3: Release build explicitly configured for Production with valid config', () {
      expect(
        () => AppConfig.validateConfig(
          env: 'production',
          rawEnvProvided: true,
          rawUrl: 'https://prodproject123456.supabase.co',
          rawKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummyproductionkey1234567890',
          isRelease: true,
        ),
        returnsNormally,
      );
    });

    test('Scenario 4: Production configuration with missing URL or anon key', () {
      // Missing URL
      expect(
        () => AppConfig.validateConfig(
          env: 'production',
          rawEnvProvided: true,
          rawUrl: '',
          rawKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummyproductionkey1234567890',
          isRelease: true,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('SUPABASE_URL was not supplied'),
        )),
      );

      // Missing Key
      expect(
        () => AppConfig.validateConfig(
          env: 'production',
          rawEnvProvided: true,
          rawUrl: 'https://prodproject123456.supabase.co',
          rawKey: '',
          isRelease: true,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('SUPABASE_ANON_KEY was missing or malformed'),
        )),
      );
    });

    test('Scenario 5: Production configuration with malformed values', () {
      // Non-HTTPS scheme
      expect(
        () => AppConfig.validateConfig(
          env: 'production',
          rawEnvProvided: true,
          rawUrl: 'http://insecure-domain.supabase.co',
          rawKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummyproductionkey1234567890',
          isRelease: true,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('must be a valid HTTPS URL'),
        )),
      );

      // Malformed key (too short)
      expect(
        () => AppConfig.validateConfig(
          env: 'production',
          rawEnvProvided: true,
          rawUrl: 'https://prodproject123456.supabase.co',
          rawKey: 'short-key',
          isRelease: true,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('SUPABASE_ANON_KEY was missing or malformed'),
        )),
      );
    });

    test('Scenario 6: Production configuration accidentally pointing to Staging project', () {
      expect(
        () => AppConfig.validateConfig(
          env: 'production',
          rawEnvProvided: true,
          rawUrl: 'https://wflhblpdszofrsobjqqq.supabase.co',
          rawKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummyproductionkey1234567890',
          isRelease: true,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('PRODUCTION ISOLATION ERROR: Production build cannot point to the Staging Supabase project URL'),
        )),
      );
    });

    test('Scenario 7: Release build with no ENVIRONMENT definition', () {
      expect(
        () => AppConfig.validateConfig(
          env: '',
          rawEnvProvided: false,
          rawUrl: '',
          rawKey: '',
          isRelease: true,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Explicit ENVIRONMENT definition is required for release builds'),
        )),
      );
    });

    test('Scenario 8: Release build with invalid or unsupported environment name', () {
      expect(
        () => AppConfig.validateConfig(
          env: 'qa',
          rawEnvProvided: true,
          rawUrl: '',
          rawKey: '',
          isRelease: true,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('UNSUPPORTED ENVIRONMENT: "qa"'),
        )),
      );

      expect(
        () => AppConfig.validateConfig(
          env: 'development',
          rawEnvProvided: true,
          rawUrl: '',
          rawKey: '',
          isRelease: true,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('UNSUPPORTED ENVIRONMENT: "development"'),
        )),
      );
    });
  });

  group('2. Database Security Hardening Verification on Staging', () {
    late SupabaseClient client;

    setUpAll(() async {
      client = SupabaseClient(
        AppConfig.supabaseUrl,
        AppConfig.supabaseAnonKey,
      );
    });

    test('Diagnostic RPC debug_list_auth_users is dropped and unavailable to anon', () async {
      try {
        await client.rpc('debug_list_auth_users');
        fail('Expected error because debug_list_auth_users should be dropped');
      } on PostgrestException catch (e) {
        expect(
          e.message.toLowerCase().contains('could not find the function') ||
              e.message.toLowerCase().contains('does not exist') ||
              e.code == 'PGRST202' ||
              e.code == '42883',
          isTrue,
          reason: 'Actual error was: ${e.message} (code: ${e.code})',
        );
      }
    });

    test('Diagnostic RPC debug_inspect_auth_user is dropped and unavailable to anon', () async {
      try {
        await client.rpc('debug_inspect_auth_user', params: {'p_email': 'test@freshcane.com'});
        fail('Expected error because debug_inspect_auth_user should be dropped');
      } on PostgrestException catch (e) {
        expect(
          e.message.toLowerCase().contains('could not find the function') ||
              e.message.toLowerCase().contains('does not exist') ||
              e.code == 'PGRST202' ||
              e.code == '42883',
          isTrue,
          reason: 'Actual error was: ${e.message} (code: ${e.code})',
        );
      }
    });

    test('Diagnostic RPC debug_get_full_auth_user is dropped and unavailable to anon', () async {
      try {
        await client.rpc('debug_get_full_auth_user', params: {'p_email': 'test@freshcane.com'});
        fail('Expected error because debug_get_full_auth_user should be dropped');
      } on PostgrestException catch (e) {
        expect(
          e.message.toLowerCase().contains('could not find the function') ||
              e.message.toLowerCase().contains('does not exist') ||
              e.code == 'PGRST202' ||
              e.code == '42883',
          isTrue,
          reason: 'Actual error was: ${e.message} (code: ${e.code})',
        );
      }
    });

    test('Unauthenticated call to admin_reset_staff_password is completely rejected', () async {
      try {
        await client.rpc(
          'admin_reset_staff_password',
          params: {
            'p_staff_user_id': '00000000-0000-0000-0000-000000000001',
            'p_new_password': 'test_new_password_123',
          },
        );
        fail('Expected unauthenticated call to admin_reset_staff_password to fail');
      } on PostgrestException catch (e) {
        expect(
          e.code == '42501' || e.message.contains('permission denied') || e.message.contains('Authentication required'),
          isTrue,
          reason: 'Actual error was: ${e.message} (code: ${e.code})',
        );
      }
    });

    test('Non-SuperAdmin caller (Cashier) is REJECTED by admin_reset_staff_password', () async {
      final cashierClient = SupabaseClient(
        AppConfig.supabaseUrl,
        AppConfig.supabaseAnonKey,
      );

      final authRes = await cashierClient.auth.signInWithPassword(
        email: 'cashier@freshcane.dev',
        password: 'cashier@123',
      );
      expect(authRes.user, isNotNull);

      try {
        await cashierClient.rpc(
          'admin_reset_staff_password',
          params: {
            'p_staff_user_id': authRes.user!.id,
            'p_new_password': 'unauthorized_attempt_pw',
          },
        );
        fail('Expected Cashier caller to be rejected by admin_reset_staff_password');
      } on PostgrestException catch (e) {
        expect(
          e.message.contains('only Super Admin can reset staff credentials'),
          isTrue,
          reason: 'Actual error was: ${e.message}',
        );
      }
    });

    test('SuperAdmin caller (Admin) is AUTHORIZED by admin_reset_staff_password', () async {
      final adminClient = SupabaseClient(
        AppConfig.supabaseUrl,
        AppConfig.supabaseAnonKey,
      );

      final adminAuth = await adminClient.auth.signInWithPassword(
        email: 'admin@freshcane.dev',
        password: 'Admin@123',
      );
      expect(adminAuth.user, isNotNull);

      final cashierProfile = await adminClient
          .from('user_profiles')
          .select('id, full_name')
          .eq('role', 'cashier')
          .limit(1)
          .single();

      final targetId = cashierProfile['id'] as String;

      final resetRes = await adminClient.rpc(
        'admin_reset_staff_password',
        params: {
          'p_staff_user_id': targetId,
          'p_new_password': 'cashier@123',
        },
      );

      expect(resetRes, isNotNull);
      expect(resetRes['success'], isTrue);
      expect(resetRes['message'], contains('Password updated successfully'));
    });
  });

  group('3. Server Account Diagnosis (Read-Only Inspection)', () {
    test('Inspect active staff profiles on Staging to determine server account state', () async {
      final adminClient = SupabaseClient(
        AppConfig.supabaseUrl,
        AppConfig.supabaseAnonKey,
      );

      final adminAuth = await adminClient.auth.signInWithPassword(
        email: 'admin@freshcane.dev',
        password: 'Admin@123',
      );
      expect(adminAuth.user, isNotNull);

      final profiles = await adminClient
          .from('user_profiles')
          .select('id, full_name, role, is_active')
          .order('role');

      // Diagnostic logging without printing sensitive secrets
      for (final p in profiles) {
        // ignore: avoid_print
        print('DIAGNOSTIC_PROFILE: role=${p['role']}, name=${p['full_name']}, active=${p['is_active']}');
      }

      final serverProfiles = profiles.where((p) => p['role'] == 'server').toList();
      expect(serverProfiles, isA<List>());
    });
  });
}
