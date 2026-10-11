import 'package:flutter/foundation.dart';

/// Immutable model representing an optional add-on for a menu item.
@immutable
class MenuAddon {
  final String id;
  final String name;
  final double price;
  final bool isActive;
  final int displayOrder;
  final String? menuItemId;

  const MenuAddon({
    required this.id,
    required this.name,
    required this.price,
    this.isActive = true,
    this.displayOrder = 0,
    this.menuItemId,
  });

  factory MenuAddon.fromJson(Map<String, dynamic> json) {
    return MenuAddon(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      menuItemId: json['menu_item_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'is_active': isActive,
      'display_order': displayOrder,
      if (menuItemId != null) 'menu_item_id': menuItemId,
    };
  }

  MenuAddon copyWith({
    String? id,
    String? name,
    double? price,
    bool? isActive,
    int? displayOrder,
    String? menuItemId,
  }) {
    return MenuAddon(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      isActive: isActive ?? this.isActive,
      displayOrder: displayOrder ?? this.displayOrder,
      menuItemId: menuItemId ?? this.menuItemId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MenuAddon &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MenuAddon($name: ₹$price)';

  /// Built-in fallback add-ons for Fresh Cane items
  static const List<MenuAddon> defaultAddons = [
    MenuAddon(id: 'addon_ginger', name: 'Fresh Ginger', price: 10.0, displayOrder: 1),
    MenuAddon(id: 'addon_lemon', name: 'Fresh Lemon', price: 5.0, displayOrder: 2),
    MenuAddon(id: 'addon_mint', name: 'Mint / Pudina', price: 5.0, displayOrder: 3),
    MenuAddon(id: 'addon_masala', name: 'Chat Masala / Pepper', price: 5.0, displayOrder: 4),
    MenuAddon(id: 'addon_honey', name: 'Pure Honey', price: 20.0, displayOrder: 5),
    MenuAddon(id: 'addon_seeds', name: 'Chia / Sabja Seeds', price: 15.0, displayOrder: 6),
    MenuAddon(id: 'addon_nannari', name: 'Nannari Syrup', price: 15.0, displayOrder: 7),
    MenuAddon(id: 'addon_shot', name: 'Extra Sugarcane Shot', price: 20.0, displayOrder: 8),
  ];
}
