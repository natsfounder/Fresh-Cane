import '../core/constants/app_constants.dart';

/// Represents a staff role account for the currently active user or linked accounts.
class StaffAccount {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final bool isCurrent;

  const StaffAccount({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.isCurrent = false,
  });

  /// Initials generated from first and last name (e.g. "Arun Kumar" -> "AK", "Kavi" -> "K").
  String get initials {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return role.isNotEmpty ? role[0].toUpperCase() : 'S';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final first = parts[0].isNotEmpty ? parts[0][0] : '';
      final second = parts[1].isNotEmpty ? parts[1][0] : '';
      return '$first$second'.toUpperCase();
    }
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// User-friendly title for the role.
  String get roleDisplayName {
    switch (role) {
      case AppConstants.roleServer:
        return 'Server';
      case AppConstants.roleCashier:
        return 'Biller';
      case AppConstants.roleSuperAdmin:
        return 'Admin';
      default:
        return role.toUpperCase();
    }
  }

  StaffAccount copyWith({
    String? id,
    String? email,
    String? fullName,
    String? role,
    bool? isCurrent,
  }) {
    return StaffAccount(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isCurrent: isCurrent ?? this.isCurrent,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StaffAccount &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email &&
          role == other.role &&
          isCurrent == other.isCurrent;

  @override
  int get hashCode => Object.hash(id, email, role, isCurrent);
}
