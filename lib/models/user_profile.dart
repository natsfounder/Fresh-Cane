import '../core/constants/app_constants.dart';

/// Immutable model representing a staff user profile in Fresh Cane POS.
///
/// Corresponds to PostgreSQL table `public.user_profiles`.
class UserProfile {
  final String id;
  final String fullName;
  final String? phone;
  final String role;
  final List<String> assignedRoles;
  final bool isActive;
  final bool isMasterSuperAdmin;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    required this.id,
    required this.fullName,
    this.phone,
    required this.role,
    this.assignedRoles = const [],
    required this.isActive,
    this.isMasterSuperAdmin = false,
    required this.createdAt,
    this.updatedAt,
  });

  /// Factory constructor to deserialize JSON returned from Supabase queries.
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final rawRole = json['role'] as String? ?? AppConstants.roleServer;
    final rawRoles = json['assigned_roles'] as List<dynamic>?;
    final List<String> parsedRoles = rawRoles != null && rawRoles.isNotEmpty
        ? rawRoles.map((e) => e.toString()).toList()
        : [rawRole];

    return UserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? 'Staff Member',
      phone: json['phone'] as String?,
      role: rawRole,
      assignedRoles: parsedRoles,
      isActive: json['is_active'] as bool? ?? true,
      isMasterSuperAdmin: (json['is_master_superadmin'] as bool?) ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Serialize to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'phone': phone,
      'role': role,
      'assigned_roles': assignedRoles,
      'is_active': isActive,
      'is_master_superadmin': isMasterSuperAdmin,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Helper checks for role authorization.
  bool get isServer => role == AppConstants.roleServer || assignedRoles.contains(AppConstants.roleServer);
  bool get isCashier => role == AppConstants.roleCashier || assignedRoles.contains(AppConstants.roleCashier);
  bool get isSuperAdmin => role == AppConstants.roleSuperAdmin || assignedRoles.contains(AppConstants.roleSuperAdmin);
  bool get isCashierOrAdmin => isCashier || isSuperAdmin;
  bool get hasValidRole => isServer || isCashier || isSuperAdmin;
  bool get isMasterSuperAdminUser => isMasterSuperAdmin || fullName.toLowerCase().contains('super administrator');

  /// Returns all assigned roles (guaranteed non-empty).
  List<String> get allRoles =>
      assignedRoles.isNotEmpty ? assignedRoles : [role];

  /// Generate two-letter initials from full name, fully crash-proof.
  String get initials {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'ST';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final first = parts[0].isNotEmpty ? parts[0][0] : '';
      final second = parts[1].isNotEmpty ? parts[1][0] : '';
      return '$first$second'.toUpperCase();
    }
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }

  UserProfile copyWith({
    String? id,
    String? fullName,
    String? phone,
    String? role,
    List<String>? assignedRoles,
    bool? isActive,
    bool? isMasterSuperAdmin,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      assignedRoles: assignedRoles ?? this.assignedRoles,
      isActive: isActive ?? this.isActive,
      isMasterSuperAdmin: isMasterSuperAdmin ?? this.isMasterSuperAdmin,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          role == other.role &&
          isActive == other.isActive;

  @override
  int get hashCode => id.hashCode ^ role.hashCode ^ isActive.hashCode;

  @override
  String toString() =>
      'UserProfile(id: $id, name: $fullName, role: $role, roles: $assignedRoles, active: $isActive)';
}
