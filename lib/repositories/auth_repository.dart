import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../services/supabase_service.dart';

/// Repository handling Supabase GoTrue authentication, password reset,
/// profile queries, and server-side admin secret verification.
class AuthRepository {
  final SupabaseClient _client;

  AuthRepository([SupabaseClient? client])
      : _client = client ?? SupabaseService.client;

  /// Expose reactive auth state changes stream.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Current authenticated user or null.
  User? get currentUser => _client.auth.currentUser;

  /// Current active session or null.
  Session? get currentSession => _client.auth.currentSession;

  /// Sign in using staff email and password.
  Future<AuthResponse> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return response;
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('Unexpected error during sign in: $e');
      throw const AuthException(
        'Unable to connect to authentication server. Please check your network.',
      );
    }
  }

  /// Request a password reset email via Supabase Auth.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (e) {
      debugPrint('AuthException during password reset: ${e.message}');
      // Don't expose whether email exists or not for security
    } catch (e) {
      debugPrint('Error sending password reset email: $e');
      throw const AuthException(
        'Unable to send password reset request. Please check your network.',
      );
    }
  }

  /// Register a new administrator account request.
  ///
  /// CRITICAL SECURITY POLICY:
  /// Newly registered accounts do NOT receive 'super_admin' privileges automatically.
  /// The user is created in Supabase Auth, but terminal administrative authorization
  /// requires explicit provisioning and role activation by the master administrator in PostgreSQL.
  Future<AuthResponse> signUpAdmin({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      );
      return response;
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('Unexpected error during admin signup: $e');
      throw const AuthException(
        'Unable to complete registration. Please check your network.',
      );
    }
  }

  /// Sign out current staff session.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('Error during sign out: $e');
      rethrow;
    }
  }

  /// Fetch staff user profile from PostgreSQL table `public.user_profiles`.
  ///
  /// Accessible only to authenticated users permitted by RLS (`public.is_staff()`).
  Future<UserProfile?> fetchUserProfile(String userId) async {
    try {
      final data = await _client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data == null) {
        return null;
      }
      return UserProfile.fromJson(data);
    } on PostgrestException catch (e) {
      debugPrint('Postgrest error fetching user profile: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Unexpected error fetching user profile: $e');
      return null;
    }
  }

  /// Fetch all active staff profiles (permitted by public.is_staff() RLS).
  Future<List<UserProfile>> fetchAllActiveProfiles() async {
    try {
      final List<dynamic> data = await _client
          .from('user_profiles')
          .select()
          .eq('is_active', true);
      return data
          .map((json) => UserProfile.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching active profiles: $e');
      return [];
    }
  }

  /// Create a new staff user account via the secure PostgreSQL RPC `admin_create_staff_user`.
  /// Supports multiple access roles for the staff member.
  /// Accessible only to authenticated 'super_admin' users.
  Future<Map<String, dynamic>> createStaffUser({
    required String email,
    required String password,
    required String fullName,
    required List<String> roles,
    String? phone,
  }) async {
    try {
      final response = await _client.rpc(
        'admin_create_staff_user',
        params: {
          'p_email': email.trim().toLowerCase(),
          'p_password': password,
          'p_full_name': fullName.trim(),
          'p_roles': roles.map((r) => r.trim().toLowerCase()).toList(),
          'p_phone': phone != null && phone.trim().isNotEmpty ? phone.trim() : null,
        },
      );
      return Map<String, dynamic>.from(response as Map);
    } on PostgrestException catch (e) {
      debugPrint('Postgrest error creating staff user: ${e.message}');
      throw AuthException(e.message);
    } catch (e) {
      debugPrint('Unexpected error creating staff user: $e');
      throw AuthException(e.toString());
    }
  }

  /// Reset a staff member's password directly via PostgreSQL RPC `admin_reset_staff_password`.
  Future<void> resetStaffPassword({
    required String userId,
    required String newPassword,
  }) async {
    try {
      await _client.rpc(
        'admin_reset_staff_password',
        params: {
          'p_staff_user_id': userId,
          'p_new_password': newPassword,
        },
      );
    } on PostgrestException catch (e) {
      debugPrint('Postgrest error resetting staff password: ${e.message}');
      throw AuthException(e.message);
    } catch (e) {
      debugPrint('Unexpected error resetting staff password: $e');
      throw AuthException(e.toString());
    }
  }
}

