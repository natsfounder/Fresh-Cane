import 'package:flutter/foundation.dart';

/// Immutable domain model representing a menu product item in Fresh Cane POS.
///
/// Corresponds to PostgreSQL table `public.menu_items`.
@immutable
class MenuItem {
  final String id;
  final String categoryId;
  final String name;
  final String? description;
  final double basePrice;
  final bool isAvailable;
  final bool isActive;
  final int displayOrder;
  final String? imageUrl;

  const MenuItem({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description,
    required this.basePrice,
    required this.isAvailable,
    required this.isActive,
    required this.displayOrder,
    this.imageUrl,
  });

  /// Factory constructor to deserialize JSON returned from Supabase.
  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      basePrice: (json['base_price'] as num).toDouble(),
      isAvailable: json['is_available'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      imageUrl: json['image_url'] as String?,
    );
  }

  /// Serialize to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'name': name,
      'description': description,
      'base_price': basePrice,
      'is_available': isAvailable,
      'is_active': isActive,
      'display_order': displayOrder,
      'image_url': imageUrl,
    };
  }

  MenuItem copyWith({
    String? id,
    String? categoryId,
    String? name,
    String? description,
    double? basePrice,
    bool? isAvailable,
    bool? isActive,
    int? displayOrder,
    String? imageUrl,
  }) {
    return MenuItem(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      basePrice: basePrice ?? this.basePrice,
      isAvailable: isAvailable ?? this.isAvailable,
      isActive: isActive ?? this.isActive,
      displayOrder: displayOrder ?? this.displayOrder,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MenuItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          categoryId == other.categoryId &&
          name == other.name &&
          basePrice == other.basePrice &&
          isAvailable == other.isAvailable &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      id.hashCode ^
      categoryId.hashCode ^
      name.hashCode ^
      basePrice.hashCode ^
      isAvailable.hashCode ^
      isActive.hashCode;

  @override
  String toString() =>
      'MenuItem(id: $id, name: $name, price: ₹$basePrice, available: $isAvailable)';
}
