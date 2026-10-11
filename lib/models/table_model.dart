import 'package:flutter/foundation.dart';

/// Immutable domain model representing a dining table in Fresh Cane POS.
///
/// Corresponds to PostgreSQL table `public.restaurant_tables`.
@immutable
class RestaurantTable {
  final String id;
  final String tableNumber;
  final int seatingCapacity;
  final String status;
  final bool isActive;
  final int activeSeatingsCount;
  final bool hasFinishedCustomers;

  const RestaurantTable({
    required this.id,
    required this.tableNumber,
    required this.seatingCapacity,
    required this.status,
    required this.isActive,
    this.activeSeatingsCount = 0,
    this.hasFinishedCustomers = false,
  });

  /// True if table is marked available and active for customer seating.
  bool get isAvailable => isActive && status == 'available';

  /// True if table is currently assigned to an active order.
  bool get isOccupied => status == 'occupied';

  /// Formatted seatings display string for the table badge.
  String get seatingsLabel {
    if (isOccupied) {
      final count = activeSeatingsCount > 0 ? activeSeatingsCount : 1;
      return count == 1 ? '1 seating' : '$count seatings';
    }
    return '$seatingCapacity seats';
  }

  /// Factory constructor to deserialize JSON returned from Supabase.
  factory RestaurantTable.fromJson(Map<String, dynamic> json) {
    int seatings = 0;
    bool hasFinished = false;

    if (json['active_seatings_count'] != null) {
      seatings = (json['active_seatings_count'] as num).toInt();
    } else if (json['table_sessions'] != null && json['table_sessions'] is List) {
      final sessions = json['table_sessions'] as List;
      final activeSessions =
          sessions.where((s) => s['status'] == 'active' || s['status'] == 'billing').toList();
      if (activeSessions.isNotEmpty) {
        final customers =
            activeSessions.first['table_session_customers'] as List?;
        if (customers != null) {
          seatings = customers.isNotEmpty ? customers.length : 1;
          hasFinished = customers.any((c) => c['status'] == 'finished');
        } else {
          seatings = 1;
        }
      }
    } else if (json['status'] == 'occupied') {
      seatings = 1;
    }

    if (json['has_finished_customers'] == true) {
      hasFinished = true;
    }

    return RestaurantTable(
      id: json['id'] as String,
      tableNumber: json['table_number'] as String,
      seatingCapacity: (json['seating_capacity'] as num?)?.toInt() ?? 4,
      status: json['status'] as String? ?? 'available',
      isActive: json['is_active'] as bool? ?? true,
      activeSeatingsCount: seatings,
      hasFinishedCustomers: hasFinished,
    );
  }

  /// Serialize to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'table_number': tableNumber,
      'seating_capacity': seatingCapacity,
      'status': status,
      'is_active': isActive,
      'active_seatings_count': activeSeatingsCount,
    };
  }

  RestaurantTable copyWith({
    String? id,
    String? tableNumber,
    int? seatingCapacity,
    String? status,
    bool? isActive,
    int? activeSeatingsCount,
    bool? hasFinishedCustomers,
  }) {
    return RestaurantTable(
      id: id ?? this.id,
      tableNumber: tableNumber ?? this.tableNumber,
      seatingCapacity: seatingCapacity ?? this.seatingCapacity,
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      activeSeatingsCount: activeSeatingsCount ?? this.activeSeatingsCount,
      hasFinishedCustomers: hasFinishedCustomers ?? this.hasFinishedCustomers,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestaurantTable &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tableNumber == other.tableNumber &&
          status == other.status &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      id.hashCode ^ tableNumber.hashCode ^ status.hashCode ^ isActive.hashCode;

  @override
  String toString() =>
      'RestaurantTable(id: $id, tableNumber: $tableNumber, status: $status, capacity: $seatingCapacity)';
}
