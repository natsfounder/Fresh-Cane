import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_cane/core/config/app_config.dart';
import 'package:fresh_cane/core/constants/app_constants.dart';
import 'package:fresh_cane/models/user_profile.dart';
import 'package:fresh_cane/presentation/auth/admin_signup_screen.dart';
import 'package:fresh_cane/presentation/auth/login_screen.dart';
import 'package:fresh_cane/state/auth_notifier.dart';
import 'package:fresh_cane/state/auth_provider.dart';
import 'package:fresh_cane/state/auth_state.dart';

class FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState.unauthenticated();
  }

  @override
  void clearError() {}

  @override
  Future<void> signInEmployee({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signInAdmin({
    required String email,
    required String password,
  }) async {}

  @override
  Future<bool> signUpAdmin({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async =>
      true;

  @override
  Future<void> sendPasswordResetEmail(String email) async {}
}

void main() {
  group('Branding Assets Verification Tests', () {
    test('Official Fresh Cane logo asset exists on disk', () {
      final logoFile = File('assets/images/fresh_cane_logo.png');
      expect(logoFile.existsSync(), isTrue,
          reason: 'assets/images/fresh_cane_logo.png must exist');
      expect(logoFile.lengthSync(), greaterThan(10000),
          reason: 'Logo file must not be empty');
    });

    test('Native launch screen drawable assets exist', () {
      final launchDrawable =
          File('android/app/src/main/res/drawable/launch_image.png');
      expect(launchDrawable.existsSync(), isTrue,
          reason: 'Native launch_image.png must exist');
    });

    test('Android launcher icons exist across all mipmap densities', () {
      final densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
      for (final density in densities) {
        final iconFile = File(
            'android/app/src/main/res/mipmap-$density/ic_launcher.png');
        expect(iconFile.existsSync(), isTrue,
            reason: 'Launcher icon for $density must exist');
      }
    });
  });

  group('Configuration & Constants Security Tests', () {
    test('AppConfig and AppConstants definition smoke test', () {
      expect(AppConfig.appName, equals('Fresh Cane'));
      expect(AppConfig.supabaseUrl, isNotEmpty);
      expect(AppConfig.supabaseAnonKey, isNotEmpty);
      expect(AppConstants.storeSettingsSingletonId,
          equals('00000000-0000-0000-0000-000000000001'));
      expect(AppConstants.roleServer, equals('server'));
      expect(AppConstants.roleCashier, equals('cashier'));
      expect(AppConstants.roleSuperAdmin, equals('super_admin'));
    });
  });

  group('UserProfile Model & RBAC Tests', () {
    test('Deserializes from valid Supabase JSON payload', () {
      final json = {
        'id': '11111111-2222-3333-4444-555555555555',
        'full_name': 'Arsath Roshan',
        'phone': '9876543210',
        'role': 'super_admin',
        'is_active': true,
        'created_at': '2026-09-12T17:00:00.000Z',
        'updated_at': '2026-09-12T17:00:00.000Z',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, equals('11111111-2222-3333-4444-555555555555'));
      expect(profile.fullName, equals('Arsath Roshan'));
      expect(profile.phone, equals('9876543210'));
      expect(profile.role, equals('super_admin'));
      expect(profile.isActive, isTrue);
      expect(profile.isSuperAdmin, isTrue);
      expect(profile.isCashierOrAdmin, isTrue);
      expect(profile.isServer, isFalse);
      expect(profile.hasValidRole, isTrue);
    });

    test('Identifies role flags accurately', () {
      final serverProfile = UserProfile(
        id: 'user-1',
        fullName: 'Server 1',
        role: AppConstants.roleServer,
        isActive: true,
        createdAt: DateTime.now(),
      );

      final cashierProfile = UserProfile(
        id: 'user-2',
        fullName: 'Cashier 1',
        role: AppConstants.roleCashier,
        isActive: true,
        createdAt: DateTime.now(),
      );

      expect(serverProfile.isServer, isTrue);
      expect(serverProfile.isCashier, isFalse);
      expect(serverProfile.isSuperAdmin, isFalse);
      expect(serverProfile.isCashierOrAdmin, isFalse);

      expect(cashierProfile.isServer, isFalse);
      expect(cashierProfile.isCashier, isTrue);
      expect(cashierProfile.isSuperAdmin, isFalse);
      expect(cashierProfile.isCashierOrAdmin, isTrue);
    });

    test('Serializes to JSON map correctly', () {
      final now = DateTime.parse('2026-09-12T17:00:00.000Z');
      final profile = UserProfile(
        id: 'uuid-123',
        fullName: 'Jane Doe',
        phone: '9123456780',
        role: 'cashier',
        isActive: true,
        createdAt: now,
      );

      final map = profile.toJson();
      expect(map['id'], equals('uuid-123'));
      expect(map['full_name'], equals('Jane Doe'));
      expect(map['role'], equals('cashier'));
      expect(map['is_active'], isTrue);
    });
  });

  group('AuthState State Container Tests', () {
    test('Initial state is unauthenticated or initial', () {
      const initial = AuthState.initial();
      expect(initial.status, equals(AuthStatus.initial));
      expect(initial.isAuthenticated, isFalse);
      expect(initial.isLoading, isFalse);

      const unauthenticated = AuthState.unauthenticated('Invalid credentials');
      expect(unauthenticated.status, equals(AuthStatus.unauthenticated));
      expect(unauthenticated.errorMessage, equals('Invalid credentials'));
      expect(unauthenticated.hasError, isTrue);
    });

    test('Loading state has isLoading true', () {
      const loading = AuthState.loading();
      expect(loading.status, equals(AuthStatus.loading));
      expect(loading.isLoading, isTrue);
      expect(loading.isAuthenticated, isFalse);
    });

    test('Error state formats correctly', () {
      const error = AuthState.error('Network failure');
      expect(error.status, equals(AuthStatus.error));
      expect(error.errorMessage, equals('Network failure'));
      expect(error.hasError, isTrue);
    });
  });

  group('LoginScreen Simplified Widget Tests', () {
    Widget createLoginTestWidget() {
      return ProviderScope(
        overrides: [
          authProvider.overrideWith(() => FakeAuthNotifier()),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      );
    }

    testWidgets('Renders Fresh Cane branding, logo, and NO mode toggle',
        (tester) async {
      await tester.pumpWidget(createLoginTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Fresh Cane'), findsWidgets);
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('EMPLOYEE LOGIN'), findsNothing);
      expect(find.text('ADMIN LOGIN'), findsNothing);
    });

    testWidgets(
        'Login screen shows Username/Email, Password, Forgot Password, Login button, and NO toggle/signup',
        (tester) async {
      await tester.pumpWidget(createLoginTestWidget());
      await tester.pumpAndSettle();

      // Fields
      expect(find.byKey(const ValueKey('login_email_field')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('login_password_field')), findsOneWidget);

      // Actions
      expect(find.byKey(const ValueKey('forgot_password_button')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('sign_in_button')), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);

      // Prohibited items MUST NOT exist
      expect(find.text('Sign Up'), findsNothing);
      expect(find.text('Sign up'), findsNothing);
      expect(find.text('EMPLOYEE LOGIN'), findsNothing);
      expect(find.text('ADMIN LOGIN'), findsNothing);
      expect(find.text('Admin Secret Code'), findsNothing);
      expect(find.byKey(const ValueKey('admin_code_field')), findsNothing);
    });

    testWidgets('Login screen validates required fields', (tester) async {
      await tester.pumpWidget(createLoginTestWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('sign_in_button')));
      await tester.tap(find.byKey(const ValueKey('sign_in_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter username or email'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });
  });

  group('AdminSignupScreen Widget & Validation Tests', () {
    Widget createSignupTestWidget() {
      return ProviderScope(
        overrides: [
          authProvider.overrideWith(() => FakeAuthNotifier()),
        ],
        child: const MaterialApp(
          home: AdminSignupScreen(),
        ),
      );
    }

    testWidgets('Renders Admin Signup fields and security disclaimer',
        (tester) async {
      await tester.pumpWidget(createSignupTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Admin Registration'), findsOneWidget);
      expect(
          find.text(
              'Administrative privileges require manual verification by the store owner.'),
          findsOneWidget);

      expect(find.byKey(const ValueKey('admin_signup_name_field')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('admin_signup_email_field')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('admin_signup_phone_field')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('admin_signup_password_field')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('admin_signup_confirm_password_field')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('admin_signup_submit_button')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('admin_signup_signin_link')),
          findsOneWidget);
    });

    testWidgets('Validates required fields and password matching',
        (tester) async {
      await tester.pumpWidget(createSignupTestWidget());
      await tester.pumpAndSettle();

      // Submit with empty fields
      await tester
          .ensureVisible(find.byKey(const ValueKey('admin_signup_submit_button')));
      await tester.tap(find.byKey(const ValueKey('admin_signup_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your full name'), findsOneWidget);
      expect(find.text('Please enter your email address'), findsOneWidget);
      expect(find.text('Password must be at least 6 characters'), findsOneWidget);

      // Enter mismatched passwords
      await tester.enterText(
          find.byKey(const ValueKey('admin_signup_name_field')), 'John Admin');
      await tester.enterText(
          find.byKey(const ValueKey('admin_signup_email_field')),
          'john@freshcane.com');
      await tester.enterText(
          find.byKey(const ValueKey('admin_signup_password_field')), 'password123');
      await tester.enterText(
          find.byKey(const ValueKey('admin_signup_confirm_password_field')),
          'mismatched');

      await tester
          .ensureVisible(find.byKey(const ValueKey('admin_signup_submit_button')));
      await tester.tap(find.byKey(const ValueKey('admin_signup_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });
  });
}
