import 'package:flutter/foundation.dart';

/// Immutable domain model representing a tax invoice bill in Fresh Cane POS.
/// Corresponds to PostgreSQL table `public.bills`.
@immutable
class Bill {
  final String id;
  final String billNumber;
  final String orderId;
  final String cashierId;
  final String? settledBy;
  final DateTime businessDate;
  final double subtotalAmount;
  final String? discountType;
  final double discountRate;
  final double discountAmount;
  final String? discountReason;
  final double taxRateSnapshot;
  final bool isTaxInclusiveSnapshot;
  final double taxAmount;
  final double roundOffAmount;
  final double finalAmount;
  final String storeNameSnapshot;
  final String? storeAddressSnapshot;
  final String? storeGstinSnapshot;
  final String? customerNameSnapshot;
  final String? customerPhoneSnapshot;
  final String status; // 'unpaid', 'paid', 'voided'
  final DateTime createdAt;
  final DateTime updatedAt;

  const Bill({
    required this.id,
    required this.billNumber,
    required this.orderId,
    required this.cashierId,
    this.settledBy,
    required this.businessDate,
    required this.subtotalAmount,
    this.discountType,
    required this.discountRate,
    required this.discountAmount,
    this.discountReason,
    required this.taxRateSnapshot,
    required this.isTaxInclusiveSnapshot,
    required this.taxAmount,
    required this.roundOffAmount,
    required this.finalAmount,
    required this.storeNameSnapshot,
    this.storeAddressSnapshot,
    this.storeGstinSnapshot,
    this.customerNameSnapshot,
    this.customerPhoneSnapshot,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPaid => status == 'paid';
  bool get isUnpaid => status == 'unpaid';
  bool get isVoided => status == 'voided';

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: json['id'] as String,
      billNumber: json['bill_number'] as String? ?? '',
      orderId: json['order_id'] as String? ?? '',
      cashierId: json['cashier_id'] as String? ?? '',
      settledBy: json['settled_by'] as String?,
      businessDate: json['business_date'] != null
          ? DateTime.parse(json['business_date'].toString())
          : DateTime.now(),
      subtotalAmount: (json['subtotal_amount'] as num?)?.toDouble() ?? 0.0,
      discountType: json['discount_type'] as String?,
      discountRate: (json['discount_rate'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      discountReason: json['discount_reason'] as String?,
      taxRateSnapshot: (json['tax_rate_snapshot'] as num?)?.toDouble() ?? 0.0,
      isTaxInclusiveSnapshot: json['is_tax_inclusive_snapshot'] as bool? ?? true,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      roundOffAmount: (json['round_off_amount'] as num?)?.toDouble() ?? 0.0,
      finalAmount: (json['final_amount'] as num?)?.toDouble() ?? 0.0,
      storeNameSnapshot: json['store_name_snapshot'] as String? ?? 'Fresh Cane',
      storeAddressSnapshot: json['store_address_snapshot'] as String?,
      storeGstinSnapshot: json['store_gstin_snapshot'] as String?,
      customerNameSnapshot: json['customer_name_snapshot'] as String?,
      customerPhoneSnapshot: json['customer_phone_snapshot'] as String?,
      status: json['status'] as String? ?? 'unpaid',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString()).toLocal()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString()).toLocal()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bill_number': billNumber,
      'order_id': orderId,
      'cashier_id': cashierId,
      'settled_by': settledBy,
      'business_date': businessDate.toIso8601String(),
      'subtotal_amount': subtotalAmount,
      'discount_type': discountType,
      'discount_rate': discountRate,
      'discount_amount': discountAmount,
      'discount_reason': discountReason,
      'tax_rate_snapshot': taxRateSnapshot,
      'is_tax_inclusive_snapshot': isTaxInclusiveSnapshot,
      'tax_amount': taxAmount,
      'round_off_amount': roundOffAmount,
      'final_amount': finalAmount,
      'store_name_snapshot': storeNameSnapshot,
      'store_address_snapshot': storeAddressSnapshot,
      'store_gstin_snapshot': storeGstinSnapshot,
      'customer_name_snapshot': customerNameSnapshot,
      'customer_phone_snapshot': customerPhoneSnapshot,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
