import 'package:flutter/material.dart';

/// Centralized Payment Method Configuration Model
class PaymentMethodItem {
  final String id;
  final String name;
  final bool isEnabled;
  final int displayOrder;

  const PaymentMethodItem({
    required this.id,
    required this.name,
    required this.isEnabled,
    this.displayOrder = 0,
  });

  factory PaymentMethodItem.fromJson(Map<String, dynamic> json) {
    return PaymentMethodItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isEnabled: json['is_enabled'] as bool? ?? true,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'is_enabled': isEnabled,
      'display_order': displayOrder,
    };
  }

  PaymentMethodItem copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    int? displayOrder,
  }) {
    return PaymentMethodItem(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }

  IconData get icon {
    switch (id.toLowerCase()) {
      case 'cash':
        return Icons.payments_outlined;
      case 'upi':
        return Icons.qr_code_rounded;
      case 'card':
        return Icons.credit_card_rounded;
      case 'bank_transfer':
      case 'bank':
        return Icons.account_balance_rounded;
      case 'net_banking':
        return Icons.language_rounded;
      default:
        return Icons.payment_rounded;
    }
  }

  /// Default predefined list if offline or table not yet migrated
  static List<PaymentMethodItem> get defaultMethods => const [
        PaymentMethodItem(id: 'cash', name: 'Cash', isEnabled: true, displayOrder: 1),
        PaymentMethodItem(id: 'upi', name: 'UPI', isEnabled: true, displayOrder: 2),
        PaymentMethodItem(id: 'card', name: 'Card', isEnabled: false, displayOrder: 3),
        PaymentMethodItem(id: 'bank_transfer', name: 'Bank Transfer', isEnabled: false, displayOrder: 4),
        PaymentMethodItem(id: 'net_banking', name: 'Net Banking', isEnabled: false, displayOrder: 5),
      ];
}
