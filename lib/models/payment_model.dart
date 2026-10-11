import 'package:flutter/foundation.dart';

/// Immutable domain model representing a multi-tender payment ledger record.
/// Corresponds to PostgreSQL table `public.payments`.
@immutable
class Payment {
  final String id;
  final String billId;
  final String paymentMethod; // 'cash', 'upi', 'card'
  final double amount;
  final String? transactionReference;
  final double? cashTendered;
  final double? changeReturned;
  final String receivedBy;
  final String status; // 'completed', 'refunded'
  final DateTime createdAt;

  const Payment({
    required this.id,
    required this.billId,
    required this.paymentMethod,
    required this.amount,
    this.transactionReference,
    this.cashTendered,
    this.changeReturned,
    required this.receivedBy,
    required this.status,
    required this.createdAt,
  });

  bool get isCash => paymentMethod == 'cash';
  bool get isUpi => paymentMethod == 'upi';
  bool get isCard => paymentMethod == 'card';

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as String,
      billId: json['bill_id'] as String,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      transactionReference: json['transaction_reference'] as String?,
      cashTendered: (json['cash_tendered'] as num?)?.toDouble(),
      changeReturned: (json['change_returned'] as num?)?.toDouble(),
      receivedBy: json['received_by'] as String? ?? '',
      status: json['status'] as String? ?? 'completed',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString()).toLocal()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bill_id': billId,
      'payment_method': paymentMethod,
      'amount': amount,
      'transaction_reference': transactionReference,
      'cash_tendered': cashTendered,
      'change_returned': changeReturned,
      'received_by': receivedBy,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
