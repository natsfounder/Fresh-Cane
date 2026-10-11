import 'package:flutter/foundation.dart';
import 'menu_addon_model.dart';
import 'menu_item_model.dart';

/// Immutable model representing an order line item in the server's active cart.
@immutable
class CartItem {
  final MenuItem menuItem;
  final int quantity;
  final List<MenuAddon> selectedAddons;
  final bool isParcel;
  final String? specialInstructions;

  const CartItem({
    required this.menuItem,
    required this.quantity,
    this.selectedAddons = const [],
    this.isParcel = false,
    this.specialInstructions,
  });

  /// Total add-on amount per single item unit.
  double get addonsPricePerUnit =>
      selectedAddons.fold(0.0, (sum, addon) => sum + addon.price);

  /// Effective unit price including selected add-ons.
  double get effectiveUnitPrice => menuItem.basePrice + addonsPricePerUnit;

  /// Total calculated line amount for this item (unit price + add-ons) * quantity.
  double get itemTotal => effectiveUnitPrice * quantity;

  CartItem copyWith({
    MenuItem? menuItem,
    int? quantity,
    List<MenuAddon>? selectedAddons,
    bool? isParcel,
    String? specialInstructions,
  }) {
    return CartItem(
      menuItem: menuItem ?? this.menuItem,
      quantity: quantity ?? this.quantity,
      selectedAddons: selectedAddons ?? this.selectedAddons,
      isParcel: isParcel ?? this.isParcel,
      specialInstructions: specialInstructions ?? this.specialInstructions,
    );
  }

  /// Convert to JSON structure expected by PostgreSQL `submit_dine_in_order` and `update_server_order`.
  Map<String, dynamic> toRpcJson() {
    final List<String> notesParts = [];
    if (isParcel) {
      notesParts.add('[PARCEL]');
    }
    if (selectedAddons.isNotEmpty) {
      final addonStr = selectedAddons
          .map((a) => '+${a.name} (+₹${a.price.toStringAsFixed(0)})')
          .join(', ');
      notesParts.add(addonStr);
    }
    if (specialInstructions != null && specialInstructions!.trim().isNotEmpty) {
      notesParts.add(specialInstructions!.trim());
    }

    final combinedInstructions = notesParts.join(' • ');

    return {
      'menu_item_id': menuItem.id,
      'quantity': quantity,
      'unit_price': effectiveUnitPrice,
      if (combinedInstructions.isNotEmpty)
        'special_instructions': combinedInstructions,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartItem &&
          runtimeType == other.runtimeType &&
          menuItem == other.menuItem &&
          quantity == other.quantity &&
          isParcel == other.isParcel &&
          listEquals(selectedAddons, other.selectedAddons) &&
          specialInstructions == other.specialInstructions;

  @override
  int get hashCode =>
      menuItem.hashCode ^
      quantity.hashCode ^
      isParcel.hashCode ^
      Object.hashAll(selectedAddons) ^
      (specialInstructions?.hashCode ?? 0);

  @override
  String toString() =>
      'CartItem(item: ${menuItem.name}, qty: $quantity, parcel: $isParcel, addons: ${selectedAddons.length}, total: ₹$itemTotal)';
}
