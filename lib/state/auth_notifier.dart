import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../core/constants/app_constants.dart';
import '../models/staff_account.dart';
import '../models/user_profile.dart';
import '../repositories/auth_repository.dart';
import 'auth_provider.dart';
import 'auth_state.dart';

/// Riverpod Notifier managing authentication lifecycle, session restoration,
/// employee vs admin login flows, and server-side secret verification.
class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription<sb.AuthState>? _authSubscription;

  @override
  AuthState build() {
    ref.onDispose(() {
      _authSubscription?.cancel();
    });

    final repo = ref.read(authRepositoryProvider);
    _authSubscription?.cancel();
    _authSubscription = repo.authStateChanges.listen((data) {
      _handleAuthEvent(data.event, data.session);
    });

    // Check for existing persisted session on app launch
    Future.microtask(() => initializeSession());

    return const AuthState.initial();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  /// Handle Supabase Auth state changes stream events.
  void _handleAuthEvent(sb.AuthChangeEvent event, sb.Session? session) {
    debugPrint('Supabase AuthEvent received: $event');
    if (event == sb.AuthChangeEvent.signedOut) {
      state = const AuthState.unauthenticated();
    } else if (event == sb.AuthChangeEvent.tokenRefreshed && session != null) {
      // Re-verify profile if needed
      if (state.userProfile == null) {
        _resolveProfile(session.user);
      }
    }
  }

  /// Initialize and verify any existing locally persisted session.
  Future<void> initializeSession() async {
    final user = _repository.currentUser;
    final session = _repository.currentSession;

    if (user == null || session == null) {
      state = const AuthState.unauthenticated();
      return;
    }

    await _resolveProfile(user);
  }

  /// Employee sign-in (email + password only).
  ///
  /// Routes according to actual server-side role in public.user_profiles.
  Future<void> signInEmployee({
    required String email,
    required String password,
  }) async {
    state = const AuthState.loading();

    try {
      final response = await _repository.signInWithEmailPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        state = const AuthState.error(
          'Authentication failed: No user returned by server.',
        );
        return;
      }

      await _resolveProfile(user);
    } on sb.AuthException catch (e) {
      debugPrint('AuthException during employee sign in: ${e.message}');
      final friendlyMessage = _mapAuthErrorMessage(e);
      state = AuthState.unauthenticated(friendlyMessage);
    } catch (e) {
      debugPrint('Unexpected error during employee sign in: $e');
      state = const AuthState.unauthenticated(
        'An unexpected network error occurred. Please check your internet connection.',
      );
    }
  }

  /// Admin sign-in (email + password).
  ///
  /// Requires:
  /// 1. Valid Supabase email/password credentials.
  /// 2. Active profile with database role == 'super_admin'.
  Future<void> signInAdmin({
    required String email,
    required String password,
  }) async {
    state = const AuthState.loading();

    try {
      // 1. Authenticate with Supabase Auth
      final response = await _repository.signInWithEmailPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        state = const AuthState.error(
          'Authentication failed: No user returned by server.',
        );
        return;
      }

      // 2. Fetch profile and verify caller has actual super_admin role
      final profile = await _repository.fetchUserProfile(user.id);
      if (profile == null) {
        await _repository.signOut();
        state = AuthState.missingProfile(user);
        return;
      }

      if (!profile.isActive) {
        await _repository.signOut();
        state = AuthState.inactive(user, profile);
        return;
      }

      if (!profile.isSuperAdmin) {
        // Non-admin attempting to use Admin Login
        await _repository.signOut();
        state = const AuthState.unauthenticated(
          'Access Denied: This staff account does not possess administrator privileges.',
        );
        return;
      }

      // Successful admin authentication
      await _resolveProfile(user);
    } on sb.AuthException catch (e) {
      debugPrint('AuthException during admin sign in: ${e.message}');
      final friendlyMessage = _mapAuthErrorMessage(e);
      state = AuthState.unauthenticated(friendlyMessage);
    } catch (e) {
      debugPrint('Unexpected error during admin sign in: $e');
      state = const AuthState.unauthenticated(
        'An unexpected network error occurred. Please check your internet connection.',
      );
    }
  }

  /// Register a new administrator account request.
  ///
  /// CRITICAL SECURITY POLICY:
  /// Self-registration does NOT grant 'super_admin' access.
  /// The user profile must be explicitly verified and assigned the 'super_admin' role
  /// in PostgreSQL by the master administrator before administrative terminal access is granted.
  Future<bool> signUpAdmin({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    state = const AuthState.loading();

    try {
      final response = await _repository.signUpAdmin(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
      );

      final user = response.user;
      if (user == null) {
        state = const AuthState.unauthenticated(
          'Registration could not be completed. Please try again.',
        );
        return false;
      }

      // Explicitly sign out right after signup so the user does not linger
      // in an unverified state without administrator approval
      await _repository.signOut();

      state = const AuthState.unauthenticated();
      return true;
    } on sb.AuthException catch (e) {
      debugPrint('AuthException during admin signup: ${e.message}');
      final friendlyMessage = _mapAuthErrorMessage(e);
      state = AuthState.unauthenticated(friendlyMessage);
      return false;
    } catch (e) {
      debugPrint('Unexpected error during admin signup: $e');
      state = const AuthState.unauthenticated(
        'An unexpected network error occurred. Please check your internet connection.',
      );
      return false;
    }
  }

  /// Request a password reset email.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _repository.sendPasswordResetEmail(email);
    } catch (e) {
      debugPrint('Password reset error: $e');
    }
  }

  /// Clear active error message.
  void clearError() {
    if (state.hasError) {
      state = state.copyWith(errorMessage: null);
    }
  }

  /// Sign out the current staff session.
  Future<void> signOut() async {
    state = const AuthState.loading();
    try {
      await _repository.signOut();
      state = const AuthState.unauthenticated();
    } catch (e) {
      debugPrint('Sign out error: $e');
      state = const AuthState.unauthenticated();
    }
  }

  /// Switch active staff role account (Instagram-style profile switching).
  Future<void> switchAccount(StaffAccount targetAccount) async {
    if (state.userProfile == null) return;

    final updatedAccounts = state.availableAccounts.map((acc) {
      final isNowCurrent = acc.role == targetAccount.role &&
          (acc.id == targetAccount.id || acc.email == targetAccount.email);
      return acc.copyWith(isCurrent: isNowCurrent);
    }).toList();

    final targetProfile = state.userProfile!.copyWith(
      id: targetAccount.id.isNotEmpty ? targetAccount.id : state.userProfile!.id,
      role: targetAccount.role,
      fullName: targetAccount.fullName.isNotEmpty
          ? targetAccount.fullName
          : state.userProfile!.fullName,
    );

    state = state.copyWith(
      userProfile: targetProfile,
      availableAccounts: updatedAccounts,
    );
  }

  /// Resolve staff profile and role from PostgreSQL `public.user_profiles`.
  Future<void> _resolveProfile(sb.User user) async {
    final UserProfile? profile = await _repository.fetchUserProfile(user.id);

    if (profile == null) {
      state = AuthState.missingProfile(user);
      return;
    }

    if (!profile.isActive) {
      state = AuthState.inactive(user, profile);
      return;
    }

    if (!profile.hasValidRole) {
      state = AuthState.unsupportedRole(user, profile);
      return;
    }

    // Resolve linked staff accounts belonging to this person
    final activeProfiles = await _repository.fetchAllActiveProfiles();
    final email = user.email ?? '';

    String emailPrefix = '';
    String domain = 'freshcane';
    if (email.contains('@')) {
      final parts = email.split('@');
      domain = parts[1];
      final localPart = parts[0];
      if (localPart.contains('.')) {
        emailPrefix = localPart.split('.')[0].toLowerCase();
      } else {
        emailPrefix = localPart.toLowerCase();
      }
    }

    final List<StaffAccount> accounts = [];

    // 1. Current active account
    accounts.add(StaffAccount(
      id: profile.id,
      email: email.isNotEmpty ? email : '${profile.role}@$domain',
      fullName: profile.fullName,
      role: profile.role,
      isCurrent: true,
    ));

    // 1.1 Add any additional assigned roles for this user
    for (final assignedRole in profile.allRoles) {
      if (!accounts.any((a) => a.role == assignedRole)) {
        accounts.add(StaffAccount(
          id: profile.id,
          email: email.isNotEmpty ? email : '$assignedRole@$domain',
          fullName: profile.fullName,
          role: assignedRole,
          isCurrent: false,
        ));
      }
    }

    // 2. Discover matching accounts belonging to this same person
    for (final other in activeProfiles) {
      if (other.id == profile.id) continue;

      bool isMatch = false;
      // Match by identical staff name (e.g. "Arun Kumar")
      if (other.fullName.trim().toLowerCase() ==
          profile.fullName.trim().toLowerCase()) {
        isMatch = true;
      }
      // Match by phone number if set
      else if (profile.phone != null &&
          profile.phone!.isNotEmpty &&
          other.phone == profile.phone) {
        isMatch = true;
      }
      // Match by username prefix (e.g. prefix "arun" with other profile "Arun")
      else if (emailPrefix.isNotEmpty &&
          other.fullName.trim().toLowerCase().startsWith(emailPrefix)) {
        isMatch = true;
      }

      if (isMatch) {
        final otherRole = other.role;
        final roleEmailString =
            otherRole == AppConstants.roleCashier ? 'cashier' : otherRole;
        final otherEmail = emailPrefix.isNotEmpty
            ? '$emailPrefix.$roleEmailString@$domain'
            : '$roleEmailString@$domain';

        if (!accounts.any((a) => a.role == other.role)) {
          accounts.add(StaffAccount(
            id: other.id,
            email: otherEmail,
            fullName: other.fullName,
            role: other.role,
            isCurrent: false,
          ));
        }
      }
    }

    state = AuthState.authenticated(
      user: user,
      userProfile: profile,
      availableAccounts: accounts,
    );
  }

  /// Map Supabase auth error codes to friendly display messages.
  String _mapAuthErrorMessage(sb.AuthException exception) {
    final msg = exception.message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'Invalid email or password. Please verify your credentials.';
    }
    if (msg.contains('email not confirmed')) {
      return 'This staff email address has not been confirmed.';
    }
    if (msg.contains('too many requests')) {
      return 'Too many failed login attempts. Please wait a few moments before trying again.';
    }
    return exception.message;
  }
}
