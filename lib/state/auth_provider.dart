import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../repositories/auth_repository.dart';
import 'auth_notifier.dart';
import 'auth_state.dart';

/// Provider exposing the singleton [AuthRepository] instance.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// Primary authentication and session state provider for Fresh Cane POS.
final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});

/// Convenience provider exposing the active staff [UserProfile] or null.
final currentStaffProfileProvider = Provider<UserProfile?>((ref) {
  return ref.watch(authProvider).userProfile;
});

/// Convenience provider checking if the current staff has cashier or super_admin privileges.
final isCashierOrAdminProvider = Provider<bool>((ref) {
  final profile = ref.watch(currentStaffProfileProvider);
  return profile != null && profile.isCashierOrAdmin;
});
