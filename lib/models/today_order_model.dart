import 'package:flutter/foundation.dart';
import 'table_session_model.dart';

/// Immutable representation of a Server's order placed during the current
/// Asia/Kolkata business day.
@immutable
class TodayOrder {
  final String orderId;
  final String orderNumber;
  final String tableId;
  final String tableNumber;
  final String? sessionId;
  final String? customerId;
  final String customerName;
  final String? customerPhone;
  final CustomerStatus customerStatus;
  final String orderStatus;

  /// Authoritative billable total amount (₹0.00 for cancelled orders).
  final double totalAmount;

  /// Raw snapshot total amount before cancellation.
  final double rawAmount;

  final int itemsCount;
  final String itemsSummary;
  final String? billNumber;
  final DateTime createdAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  const TodayOrder({
    required this.orderId,
    required this.orderNumber,
    required this.tableId,
    required this.tableNumber,
    this.sessionId,
    this.customerId,
    required this.customerName,
    this.customerPhone,
    required this.customerStatus,
    required this.orderStatus,
    required this.totalAmount,
    required this.rawAmount,
    required this.itemsCount,
    required this.itemsSummary,
    this.billNumber,
    required this.createdAt,
    this.cancelledAt,
    this.cancellationReason,
  });

  /// True if the order has been cancelled and contributes ₹0 to billing.
  bool get isCancelled => orderStatus == 'cancelled';

  /// True if the order is active, served, or completed.
  bool get isActive => !isCancelled;

  /// True if this order was consolidated into a primary order during billing,
  /// leaving 0 items and ₹0 amount. This ghost order should be hidden from
  /// Today's Orders list and metrics.
  bool get isConsolidatedEmpty => !isCancelled && itemsCount == 0 && totalAmount == 0;

  /// Billable amount contribution for this order (strictly ₹0 if cancelled).
  double get billableAmount => isCancelled ? 0.0 : totalAmount;

  factory TodayOrder.fromJson(Map<String, dynamic> json) {
    return TodayOrder(
      orderId: json['order_id'] as String,
      orderNumber: json['order_number'] as String? ?? '',
      tableId: json['table_id'] as String? ?? '',
      tableNumber: json['table_number'] as String? ?? '',
      sessionId: json['session_id'] as String?,
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String? ?? 'Customer',
      customerPhone: json['customer_phone'] as String?,
      customerStatus: CustomerStatus.fromString(json['customer_status'] as String?),
      orderStatus: json['order_status'] as String? ?? 'open',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      rawAmount: (json['raw_amount'] as num?)?.toDouble() ??
          (json['total_amount'] as num?)?.toDouble() ??
          0.0,
      itemsCount: (json['items_count'] as num?)?.toInt() ?? 0,
      itemsSummary: json['items_summary'] as String? ?? '',
      billNumber: json['bill_number'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString()).toLocal()
          : DateTime.now(),
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.tryParse(json['cancelled_at'].toString())?.toLocal()
          : null,
      cancellationReason: json['cancellation_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order_id': orderId,
      'order_number': orderNumber,
      'table_id': tableId,
      'table_number': tableNumber,
      'session_id': sessionId,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_status': customerStatus.toDbString(),
      'order_status': orderStatus,
      'total_amount': totalAmount,
      'raw_amount': rawAmount,
      'items_count': itemsCount,
      'items_summary': itemsSummary,
      'bill_number': billNumber,
      'created_at': createdAt.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancellation_reason': cancellationReason,
    };
  }
}
