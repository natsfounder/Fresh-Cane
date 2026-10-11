import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/staff_account.dart';
import '../models/user_profile.dart';

/// Status enum for staff authentication and profile verification.
enum AuthStatus {
  /// App startup / checking persisted local session
  initial,

  /// In-flight sign-in operation
  loading,

  /// No active authenticated user session
  unauthenticated,

  /// Authenticated and verified active staff profile with valid role
  authenticated,

  /// Authenticated in auth.users, but no corresponding row in public.user_profiles
  missingProfile,

  /// Authenticated, but user_profiles.is_active is false
  inactive,

  /// Authenticated, but role is not server, cashier, or super_admin
  unsupportedRole,

  /// Authentication or network failure
  error,
}

/// Immutable state container for authentication and RBAC.
class AuthState {
  final AuthStatus status;
  final User? user;
  final UserProfile? userProfile;
  final String? errorMessage;
  final List<StaffAccount> availableAccounts;

  const AuthState({
    required this.status,
    this.user,
    this.userProfile,
    this.errorMessage,
    this.availableAccounts = const [],
  });

  const AuthState.initial()
      : status = AuthStatus.initial,
        user = null,
        userProfile = null,
        errorMessage = null,
        availableAccounts = const [];

  const AuthState.unauthenticated([String? message])
      : status = AuthStatus.unauthenticated,
        user = null,
        userProfile = null,
        errorMessage = message,
        availableAccounts = const [];

  const AuthState.loading()
      : status = AuthStatus.loading,
        user = null,
        userProfile = null,
        errorMessage = null,
        availableAccounts = const [];

  const AuthState.authenticated({
    required this.user,
    required this.userProfile,
    this.availableAccounts = const [],
  })  : status = AuthStatus.authenticated,
        errorMessage = null;

  const AuthState.missingProfile(this.user)
      : status = AuthStatus.missingProfile,
        userProfile = null,
        availableAccounts = const [],
        errorMessage =
            'Account authenticated, but staff profile is not provisioned in the store database.';

  AuthState.inactive(this.user, UserProfile profile)
      : status = AuthStatus.inactive,
        userProfile = profile,
        availableAccounts = const [],
        errorMessage =
            'Staff account for ${profile.fullName} has been deactivated. Please contact your store administrator.';

  AuthState.unsupportedRole(this.user, UserProfile profile)
      : status = AuthStatus.unsupportedRole,
        userProfile = profile,
        availableAccounts = const [],
        errorMessage =
            'Account possesses an unassigned or unsupported role (${profile.role}).';

  const AuthState.error(String message)
      : status = AuthStatus.error,
        user = null,
        userProfile = null,
        availableAccounts = const [],
        errorMessage = message;

  bool get isLoading => status == AuthStatus.loading;
  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
  bool get hasMultipleAccounts => availableAccounts.length > 1;

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    UserProfile? userProfile,
    String? errorMessage,
    List<StaffAccount>? availableAccounts,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      userProfile: userProfile ?? this.userProfile,
      errorMessage: errorMessage ?? this.errorMessage,
      availableAccounts: availableAccounts ?? this.availableAccounts,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          user?.id == other.user?.id &&
          userProfile == other.userProfile &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode =>
      status.hashCode ^
      (user?.id.hashCode ?? 0) ^
      (userProfile.hashCode) ^
      (errorMessage.hashCode);

  @override
  String toString() =>
      'AuthState(status: $status, user: ${user?.email}, role: ${userProfile?.role}, accounts: ${availableAccounts.length}, error: $errorMessage)';
}
