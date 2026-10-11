import 'package:flutter/foundation.dart';

/// Immutable domain model representing a customer in Fresh Cane POS.
///
/// Corresponds to PostgreSQL table `public.customers`.
@immutable
class Customer {
  final String id;
  final String phone;
  final String? name;

  const Customer({
    required this.id,
    required this.phone,
    this.name,
  });

  /// Factory constructor to deserialize JSON returned from Supabase.
  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      phone: json['phone'] as String,
      name: json['name'] as String?,
    );
  }

  /// Serialize to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'name': name,
    };
  }

  Customer copyWith({
    String? id,
    String? phone,
    String? name,
  }) {
    return Customer(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      name: name ?? this.name,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Customer &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          phone == other.phone &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ phone.hashCode ^ (name?.hashCode ?? 0);

  @override
  String toString() => 'Customer(id: $id, phone: $phone, name: $name)';
}
