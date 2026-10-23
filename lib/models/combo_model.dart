import 'package:flutter/foundation.dart';

/// Immutable domain model representing a food item inside a Combo.
@immutable
class ComboItem {
  final String id;
  final String menuItemId;
  final String itemName;
  final double basePrice;
  final int quantity;

  const ComboItem({
    required this.id,
    required this.menuItemId,
    required this.itemName,
    required this.basePrice,
    this.quantity = 1,
  });

  factory ComboItem.fromJson(Map<String, dynamic> json) {
    return ComboItem(
      id: json['id']?.toString() ?? '',
      menuItemId: json['menu_item_id']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      basePrice: (json['base_price'] as num?)?.toDouble() ?? 0.0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'menu_item_id': menuItemId,
      'item_name': itemName,
      'base_price': basePrice,
      'quantity': quantity,
    };
  }

  ComboItem copyWith({
    String? id,
    String? menuItemId,
    String? itemName,
    double? basePrice,
    int? quantity,
  }) {
    return ComboItem(
      id: id ?? this.id,
      menuItemId: menuItemId ?? this.menuItemId,
      itemName: itemName ?? this.itemName,
      basePrice: basePrice ?? this.basePrice,
      quantity: quantity ?? this.quantity,
    );
  }
}

/// Immutable domain model representing a Combo in Fresh Cane POS.
@immutable
class Combo {
  final String id;
  final String name;
  final String? description;
  final double price;
  final bool isAvailable;
  final bool isActive;
  final int displayOrder;
  final String? menuItemId;
  final int itemsCount;
  final List<ComboItem> items;
  final DateTime? createdAt;

  const Combo({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.isAvailable = true,
    this.isActive = true,
    this.displayOrder = 0,
    this.menuItemId,
    this.itemsCount = 0,
    this.items = const [],
    this.createdAt,
  });

  factory Combo.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    final itemsList = rawItems
        .map((i) => ComboItem.fromJson(Map<String, dynamic>.from(i as Map)))
        .toList();

    return Combo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      isAvailable: json['is_available'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      menuItemId: json['menu_item_id']?.toString(),
      itemsCount: (json['items_count'] as num?)?.toInt() ?? itemsList.fold(0, (sum, it) => sum + it.quantity),
      items: itemsList,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'is_available': isAvailable,
      'is_active': isActive,
      'display_order': displayOrder,
      'menu_item_id': menuItemId,
      'items_count': itemsCount,
      'items': items.map((i) => i.toJson()).toList(),
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Combo copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    bool? isAvailable,
    bool? isActive,
    int? displayOrder,
    String? menuItemId,
    int? itemsCount,
    List<ComboItem>? items,
    DateTime? createdAt,
  }) {
    return Combo(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      isAvailable: isAvailable ?? this.isAvailable,
      isActive: isActive ?? this.isActive,
      displayOrder: displayOrder ?? this.displayOrder,
      menuItemId: menuItemId ?? this.menuItemId,
      itemsCount: itemsCount ?? this.itemsCount,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
