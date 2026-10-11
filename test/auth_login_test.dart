import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fresh_cane/core/config/app_config.dart';

void main() {
  late SupabaseClient client;

  setUpAll(() {
    client = SupabaseClient(
      AppConfig.supabaseUrl,
      AppConfig.supabaseAnonKey,
    );
  });

  test('Server staff account can sign in and resolve server profile', () async {
    final authRes = await client.auth.signInWithPassword(
      email: 'server@freshcane.dev',
      password: 'server@123',
    );

    expect(authRes.user, isNotNull);
    expect(authRes.user!.email, equals('server@freshcane.dev'));

    final profile = await client
        .from('user_profiles')
        .select()
        .eq('id', authRes.user!.id)
        .maybeSingle();

    expect(profile, isNotNull);
    expect(profile!['role'], equals('server'));
    expect(profile['is_active'], isTrue);
  });

  test('Admin account can sign in and resolve super_admin profile', () async {
    final authRes = await client.auth.signInWithPassword(
      email: 'admin@freshcane.dev',
      password: 'Admin@123',
    );

    expect(authRes.user, isNotNull);
    expect(authRes.user!.email, equals('admin@freshcane.dev'));

    final profile = await client
        .from('user_profiles')
        .select()
        .eq('id', authRes.user!.id)
        .maybeSingle();

    expect(profile, isNotNull);
    expect(profile!['role'], equals('super_admin'));
    expect(profile['is_active'], isTrue);
  });

  test('Cashier account can sign in and resolve cashier profile', () async {
    final authRes = await client.auth.signInWithPassword(
      email: 'cashier@freshcane.dev',
      password: 'cashier@123',
    );

    expect(authRes.user, isNotNull);
    expect(authRes.user!.email, equals('cashier@freshcane.dev'));

    final profile = await client
        .from('user_profiles')
        .select()
        .eq('id', authRes.user!.id)
        .maybeSingle();

    expect(profile, isNotNull);
    expect(profile!['role'], equals('cashier'));
    expect(profile['is_active'], isTrue);
  });
}

